-- This script is designed for use in Mudlet to manage inventory tracking via dynamic JSON data

-- URL to fetch JSON data for inventory
local jsonUrl = "https://raw.githubusercontent.com/legimia/ViVendorScanner/main/store.json"
local filePath = getMudletHomeDir() .. "/store.json"

-- Variables to track scanning state
local isScanning = false -- Whether scanning is active
local storeQueue = {} -- Queue of stores for scanning
local currentStoreIndex = 0 -- Current index in the store queue
local itemTriggers = {} -- Separate table for item triggers
local activeTempTriggers = {} -- Track temporary triggers

-- Function to download the JSON file
function downloadInventoryFile(callback)
    print("Starting download from:", jsonUrl)

    downloadFile(filePath, jsonUrl, function(_, status)
        print("Download callback triggered. Status:", status)

        if status ~= 0 then
            print("Failed to download inventory data. HTTP Status:", status)
            return
        end

        if callback then
            callback() -- Execute any additional logic if provided
        end
    end)
end

function processInventoryFile()
    local file = io.open(filePath, "r")
    if not file then
        print("Failed to read downloaded JSON file.")
        return
    end

    local content = file:read("*all")
    file:close()
    print("File content loaded (length: " .. #content .. "):", content)

    if content == "" or not content then
        print("JSON file is empty or missing.")
        return
    end

    local data, err = yajl.to_value(content)
    if err then
        print("JSON parsing error:", err)
        return
    end

    if not data then
        print("Parsed data is nil. Check JSON structure.")
        return
    end

    if type(data) ~= "table" then
        print("Parsed data is not a table. Ensure JSON structure is correct.")
        return
    end

    -- Transform the JSON structure into the expected Lua table format
    local inventories = {}
    if data.stores then
        for storeName, storeDetails in pairs(data.stores) do
            local storeNumber = storeDetails.store_number or 0 -- Store number for reference
            inventories[storeName] = {store_number = storeNumber, items = {}}
            for itemName, itemCount in pairs(storeDetails.inventory or {}) do
                inventories[storeName].items[itemName] = {needed = itemCount, count = 0}
            end
        end
    end

    _G.inventories = inventories
    print("Inventory data successfully loaded and transformed!")

    initializeStoreQueue() -- Initialize the store queue
end

-- Function to process item triggers separately
function processItemTriggers()
    local file = io.open(filePath, "r")
    if not file then
        print("Failed to read downloaded JSON file for triggers.")
        return
    end

    local content = file:read("*all")
    file:close()
    print("File content loaded for triggers (length: " .. #content .. "):", content)

    if content == "" or not content then
        print("JSON file is empty or missing for triggers.")
        return
    end

    local data, err = yajl.to_value(content)
    if err then
        print("JSON parsing error:", err)
        return
    end

    if not data or not data.items then
        print("No items found in JSON to create triggers. Data content:", yajl.to_string(data))
        return
    end

    -- Populate itemTriggers table
    itemTriggers = {}
    for itemName, itemDetails in pairs(data.items) do
        if itemDetails.trigger then
            itemTriggers[itemName] = itemDetails.trigger
            print("Trigger added for item:", itemName, "Pattern:", itemDetails.trigger)
        else
            print("No trigger defined for item:", itemName)
        end
    end

    if next(itemTriggers) == nil then
        print("No triggers were successfully added. Check JSON structure.")
    else
        print("All triggers successfully added.")
    end
end

-- Function to initialize temporary triggers from itemTriggers table
function initializeTempDynamicTriggers()
    clearTempDynamicTriggers() -- Ensure old triggers are cleared before creating new ones
    for itemName, pattern in pairs(itemTriggers) do
        local fullPattern = "^ {3}" .. pattern .. " \\((\\d+)\\)$"
        local trigger = tempRegexTrigger(fullPattern, function(matches)
            -- Debugging matches table
            print("Debug Matches Table for item:", itemName, "Matches:", matches)

            -- Validate matches table
            if not matches or type(matches) ~= "table" then
                print("Error: Matches table is nil or invalid for pattern:", fullPattern)
                return
            end

            -- Log all matches
            for index, value in pairs(matches) do
                print("Match Index:", index, "Value:", value)
            end

            -- Ensure matches[2] exists
            if not matches[2] then
                print("Error: matches[2] is nil for item:", itemName, "Pattern:", fullPattern)
                return
            end

            print("Trigger matched for item:", itemName, "Matched Line:", matches[1])
            local matchedCount = tonumber(matches[2])
            if matchedCount then
                add_to_count("generic_store", itemName, matchedCount)
                print("Count added for item:", itemName, "Count:", matchedCount)
            else
                print("Failed to parse count from trigger match.")
            end
        end)

        table.insert(activeTempTriggers, {
            id = trigger,
            itemName = itemName,
            pattern = fullPattern
        })
        print("Temporary dynamic trigger created for:", itemName, "with pattern:", fullPattern)
    end
end

-- Function to clear all temporary triggers
function clearTempDynamicTriggers()
    for _, trigger in ipairs(activeTempTriggers) do
        killTrigger(trigger.id)
    end
    activeTempTriggers = {} -- Reset the table
    print("All temporary dynamic triggers cleared.")
end

-- Function to initialize the store queue from inventories
function initializeStoreQueue()
    storeQueue = {}
    safeAccessInventories(function(inventories)
        for storeName, storeData in pairs(inventories) do
            table.insert(storeQueue, {name = storeName, number = storeData.store_number})
        end
        table.sort(storeQueue, function(a, b) return a.number < b.number end)
    end)
    print("Store queue initialized.")
end

-- Function to create a trigger to call processNextStore
function createProcessNextStoreTrigger()
    -- Create a temporary trigger to detect the end of vendor list processing
    local trigger = tempRegexTrigger("^%d+ vendor%(s%) found%.$", function()
        print("Vendor list completed. Moving to next store.")
        processNextStore()
    end)
    print("Temporary trigger created to progress to the next store.")
    return trigger
end

-- Function to initialize and clear the trigger as needed
function manageProcessNextStoreTrigger()
    local trigger = createProcessNextStoreTrigger()
    -- Clear this trigger when scanning ends
    tempTimer(1, function()
        if not isScanning then
            killTrigger(trigger)
            print("Temporary trigger for processNextStore cleared.")
        end
    end)
end

-- Function to process the next store in the queue
function processNextStore()
    if not isScanning then
        print("Scanning is not active.")
        return
    end

    currentStoreIndex = currentStoreIndex + 1
    if currentStoreIndex > #storeQueue then
        print("All stores have been processed.")
        isScanning = false -- Stop scanning
        clearTempDynamicTriggers() -- Clear temporary triggers after scanning
        return
    end

    local store = storeQueue[currentStoreIndex]
    if store then
        print("Processing store:", store.name, "Number:", store.number)
        sentStore = store.name -- Set the global sentStore
        send("vendor clan inventory " .. store.number)
    else
        print("Invalid store entry in queue.")
    end
end

-- Function to start scanning
function startStoreScanning()
    if isScanning then
        print("Scanning is already in progress.")
        return
    end

    reset_inventory_counts()
    isScanning = true

    -- Process and initialize dynamic triggers
    processItemTriggers()
    initializeTempDynamicTriggers()
    processInventoryFile()
    initializeStoreQueue()
    currentStoreIndex = 0
    
    -- Create a trigger to progress the queue
    manageProcessNextStoreTrigger()

    processNextStore() -- Start processing the first store
end

-- Function to safely access inventories and execute a callback
function safeAccessInventories(callback)
    if not _G.inventories then
        print("Inventories not yet loaded. Please wait.")
        return
    end
    callback(_G.inventories)
end

-- Startup function to initialize everything
function startup()
    -- Download and process JSON data
    downloadInventoryFile(function()
        print("JSON file downloaded successfully.")
    end)
end

-- Add debugging to verify triggers are set
function debugTriggers()
    print("Debugging Triggers:")
    for itemName, pattern in pairs(itemTriggers) do
        print("Item:", itemName, "Pattern:", pattern)
    end
end

function reset_inventory_counts()
    safeAccessInventories(function(inventories)
        for storeName, storeData in pairs(inventories) do
            for itemName, itemData in pairs(storeData.items) do
                itemData.count = 0 -- Reset the count to zero
            end
        end
        print("All inventory counts have been reset.")
    end)
end

function debugActiveTriggers()
    print("Active Temporary Triggers:")
    for _, trigger in ipairs(activeTempTriggers) do
        print("Trigger ID:", trigger.id, "Item Name:", trigger.itemName, "Pattern:", trigger.pattern)
    end
end


-- Call the startup function
startup()

-- Optionally debug triggers
debugTriggers()
