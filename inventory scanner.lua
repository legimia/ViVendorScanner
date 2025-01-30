-- This script is designed for use in Mudlet to manage inventory tracking via dynamic JSON data



-- URL to fetch JSON data for inventory
local jsonUrl = "https://raw.githubusercontent.com/legimia/ViVendorScanner/main/store.json"
local filePath = getMudletHomeDir() .. "/store.json"

-- Variables to track scanning state
debugingScan = false -- show debug information
isScanning = false -- Whether scanning is active
local storeQueue = {} -- Queue of stores for scanning
local currentStoreIndex = 0 -- Current index in the store queue
local itemTriggers = {} -- Separate table for item triggers
local sentStore = "" -- Track the current store being processed

-- Global variable to store the callback function
local downloadCallback = nil


-- Register the event handler for download completion
registerAnonymousEventHandler("sysDownloadDone", "onFileDownloaded")
registerAnonymousEventHandler("sysDownloadError", "onDownloadFailed")
-- Function to manually start the inventory update
function startInventoryUpdate()
    if debugingScan then print("Manual inventory update initiated...") end
    downloadCallback = onDownloadSuccess -- Store the callback in a global variable
    downloadInventoryFile()
end

-- Function to download the JSON file without inline callback
function downloadInventoryFile()
    print("Starting download from:", jsonUrl)
    downloadFile(filePath, jsonUrl)
end

-- Function called when the file download completes
function onFileDownloaded(event, filename)
    if filename == filePath then
        if debugingScan then print("Download completed successfully:", filename) end
        if downloadCallback then
            if processInventoryFile() then
                if debugingScan then print("New inventory data processed successfully.") end
            else
                if debugingScan then print("Error processing downloaded inventory file.") end
            end
            downloadCallback = nil -- Reset the callback after execution
        end
    end
end

function onDownloadFailed(event, reason)
    if debugingScan then print("Download failed:", reason) end
end

function onDownloadSuccess()
    if debugingScan then print("JSON file downloaded successfully.") end
    
    if not _G.fullInventoryData then
        processInventoryFile()
    end

    initializePersistentDynamicTriggers()
end

-- Function to process inventory file
function processInventoryFile()
    local file = io.open(filePath, "r")
    if not file then
        print("Error: Unable to open inventory file.")
        return false
    end

    local content = file:read("*all")
    file:close()

    -- Use yajl.to_value instead of parseJson
    local data, err = yajl.to_value(content)
    if not data then
        print("Error parsing JSON:", err)
        return false
    end

    -- Store all data globally
    _G.fullInventoryData = data

    -- Extract item triggers safely
    _G.itemTriggers = {}
    for itemName, itemDetails in pairs(data.items or {}) do
        if itemDetails and itemDetails.trigger then
            _G.itemTriggers[itemName] = itemDetails.trigger
        end
    end

    _G.inventories = {}
    for storeName, storeDetails in pairs(data.stores or {}) do
        _G.inventories[storeName] = {
            store_number = storeDetails.store_number or 0,
            items = {}
        }
        for itemName, itemCount in pairs(storeDetails.inventory or {}) do
            _G.inventories[storeName].items[itemName] = {
                needed = itemCount,
                count = 0
            }
        end
    end

    if debugingScan then print("Inventory file processed successfully.") end
    initializePersistentDynamicTriggers()
    return true
end

-- Function to initialize pers
function initializePersistentDynamicTriggers()
    for itemName, triggerData in pairs(_G.itemTriggers) do
        createTrigger(itemName, triggerData)
    end
end


function createTrigger(itemName, triggerData)
    local triggerPatterns = {}

    if type(triggerData) == "table" then
        for _, pattern in ipairs(triggerData) do
            local escapedPattern = pattern:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%[%]])", "\\%1")
            table.insert(triggerPatterns, "^ {3}" .. escapedPattern .. " \\((\\d+)\\)?$")
        end
    else
        local escapedPattern = triggerData:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?%[%]])", "\\%1")
        table.insert(triggerPatterns, "^ {3}" .. escapedPattern .. " \\((\\d+)\\)?$")
    end

    -- Ensure we pass all patterns as a table to permRegexTrigger
    if exists("DynamicTrigger_" .. itemName, "trigger") == 0 then
        permRegexTrigger("DynamicTrigger_" .. itemName, "DynamicVendorTriggers", triggerPatterns, [[
            if not matches or not matches[2] then return end
            local matchedCount = tonumber(matches[2])
            if matchedCount then
                if isScanning then add_to_count("]] .. itemName .. [[", matchedCount) end
                if debugingScan then print("Count updated for item:", "]] .. itemName .. [[", "New count:", matchedCount) end
            end
        ]])

        if debugingScan then print("Persistent trigger created for:", itemName, "Patterns:", table.concat(triggerPatterns, ", ")) end
    else
        if debugingScan then print("Warning: Trigger for", itemName, "already exists. Skipping.") end
    end
end



function checkExistingInventoryFile()
    local file = io.open(filePath, "r")
    if file then
        if debugingScan then print("Existing inventory file found:", filePath) end
        file:close()
        return true
    else
        if debugingScan then print("No existing inventory file found.") end
        return false
    end
end

-- Function to display inventory counts
function display_store_inventory(store)
    if store == nil then
        for storeName, _ in pairs(_G.inventories) do
            if storeName ~= "QuarterMaster" then
                display_store_inventory(storeName)
            end
        end
        return
    end

    if store == "QuarterMaster" then
        if debugingScan then print("Skipping store:", store) end
        return
    end

    if not _G.inventories[store] then
        print("Error: Store not found:", store)
        return
    end

    print("----------------------------------------")
    print(string.format("|%-38s|", store))
    print("----------------------------------------")
    print("| Product Name        | Needed - Count |")
    print("----------------------------------------")

    local hasItems = false

    for itemName, itemData in pairs(_G.inventories[store].items) do
        local needed = itemData.needed or 0
        local count = itemData.count or 0
        local difference = needed - count

        if difference > 0 then
            print(string.format("| %-18s | %-15d |", itemName, difference))
            hasItems = true
        end
    end

    if not hasItems then
        print("| No items needed at this store.       |")
    end

    print("----------------------------------------")
end

function display_quartermaster_inventory()
    local store = "QuarterMaster"

    if not _G.inventories[store] then
        print("Error: Store not found:", store)
        return
    end

    print("--------------------------------------------------------")
    print(string.format("|%-54s|", store))
    print("--------------------------------------------------------")
    print("| Product Name          | Needed | Count | Status      |")
    print("--------------------------------------------------------")

    local hasItems = false

    for itemName, itemData in pairs(_G.inventories[store].items) do
        local needed = itemData.needed or 0
        local count = itemData.count or 0
        local percentage = (count / needed) * 100

        local status = "OK"
        if needed > 0 and percentage < 20 then
            status = "LOW"
        end

        print(string.format("| %-20s | %-6d | %-5d | %-10s |", itemName, needed, count, status))
        hasItems = true
    end

    if not hasItems then
        print("| No items found in QuarterMaster.      |")
    end

    print("--------------------------------------------------------")
end

function processNextStore()
    if currentStoreIndex >= #storeQueue then
        completeScan()
        return
    end

    currentStoreIndex = currentStoreIndex + 1
    sentStore = storeQueue[currentStoreIndex]
    
    if not _G.inventories[sentStore] then
        print("Error: Store not found:", sentStore)
        processNextStore()
        return
    end

    local storeNumber = _G.inventories[sentStore].store_number or 0
    if storeNumber > 0 then
        if debugingScan then print("Processing store:", sentStore, "Store Number:", storeNumber) end
        send("vendor clan inventory " .. storeNumber)
    else
        if debugingScan then print("Skipping store:", sentStore, "Invalid store number.") end
        processNextStore()
    end
end

function initializeStoreQueue()
    storeQueue = {}
    for storeName, _ in pairs(_G.inventories) do
        table.insert(storeQueue, storeName)
    end
    if debugingScan then print("Store queue initialized with", #storeQueue, "stores.") end
end

function startScanning()
    if isScanning then
        print("Scanning is already in progress.")
        return
    end

    resetScan()
    reset_inventory_counts()
    storeQueue = {} -- Ensure queue is empty before adding stores
    isScanning = true

    if #storeQueue == 0 then
        initializeStoreQueue()
    end

    if #storeQueue > 0 then
        processNextStore()
    else
        print("No stores available for scanning.")
        isScanning = false
    end
end

function resetScan()
    isScanning = false
    storeQueue = {}
    currentStoreIndex = 0
    sentStore = ""
    --clearPersistentDynamicTriggers()
    print("Scanning process has been reset.")
end

function add_to_count(item, count)
    if _G.inventories[sentStore] and _G.inventories[sentStore].items[item] then
        local currentCount = _G.inventories[sentStore].items[item].count or 0
        _G.inventories[sentStore].items[item].count = currentCount + count
        if debugingScan then print("Updated count for", item, "in store", sentStore, "to:", _G.inventories[sentStore].items[item].count) end
    else
        if debugingScan then print("Error: Invalid store or item:", sentStore, item) end
    end
end

function reset_inventory_counts()
    for store, storeData in pairs(_G.inventories or {}) do
        for item, _ in pairs(storeData.items) do
            storeData.items[item].count = 0
        end
    end
    print("All inventory counts have been reset.")
end

function display_total_needed_minus_count()
    if not _G.inventories then
        print("Error: No inventory data available. Please load inventory first.")
        return
    end

    local aggregatedItems = {}

    -- Aggregate item counts from all stores except QuarterMaster
    for storeName, storeData in pairs(_G.inventories) do
        if storeName ~= "QuarterMaster" then
            for itemName, itemData in pairs(storeData.items) do
                if not aggregatedItems[itemName] then
                    aggregatedItems[itemName] = { needed = 0, count = 0 }
                end
                aggregatedItems[itemName].needed = aggregatedItems[itemName].needed + (itemData.needed or 0)
                aggregatedItems[itemName].count = aggregatedItems[itemName].count + (itemData.count or 0)
            end
        end
    end

    -- Sort items alphabetically by name
    local sortedKeys = {}
    for itemName in pairs(aggregatedItems) do
        table.insert(sortedKeys, itemName)
    end
    table.sort(sortedKeys)

    print("----------------------------------------")
    print("| Product Name        | Needed         |")
    print("----------------------------------------")

    for _, itemName in ipairs(sortedKeys) do
        local itemData = aggregatedItems[itemName]
        local difference = itemData.needed - itemData.count
        if difference > 0 then
            print(string.format("| %-18s | %-15d |", itemName, difference))
        end
    end

    print("----------------------------------------")
end

function checkInventoryCompletion()
    local complete = true
    for store, storeData in pairs(_G.inventories or {}) do
        for item, itemData in pairs(storeData.items) do
            local remaining = itemData.needed - itemData.count
            if remaining > 0 then
                if debugingScan then print("Store:", store, "Item:", item, "Still needed:", remaining) end
                complete = false
            end
        end
    end

    if complete then
        print("All inventory items are fully stocked.")
    else
        print("Inventory check completed. Some items are still needed.")
    end
end

function completeScan()
    print("Scanning completed successfully.")
    checkInventoryCompletion()
    isScanning = false
end

function manualRefreshInventory()
    print("Manually refreshing inventory...")
    downloadInventoryFile()
end

function scanStartup()
    print("Starting inventory system...")
        if exists("DynamicVendorTriggers", "trigger") == 0 then
        permGroup("DynamicVendorTriggers", "trigger")
        if debugingScan then print("Trigger group 'DynamicVendorTriggers' created.") end

    else
        if debugingScan then print("Warning: Trigger group 'DynamicVendorTriggers' already exists.") end
    end
    setupVendScanAliases()
    setupVendorTrigger()
  
    -- Try to load the existing file first
    local success = processInventoryFile()
    if success then
        print("Existing inventory file loaded successfully.")
    else
        print("No valid inventory file found. Downloading new data...")
        startInventoryUpdate() -- Trigger the download if no valid data exists
    end
end

function debugInventory()
    print("Debugging Inventory Data:")
    for storeName, storeDetails in pairs(_G.inventories or {}) do
        print("Store:", storeName, "Number:", storeDetails.store_number)
        for itemName, itemCount in pairs(storeDetails.items) do
            print("Item:", itemName, "Needed:", itemCount, "Count:", storeDetails.items[itemName].count or 0)
        end
    end
end

function setupVendorTrigger()
    if exists("VendorCountTrigger", "trigger") == 0 then
        permSubstringTrigger("VendorCountTrigger", "DynamicVendorTriggers", {"vendor(s) found."}, [[
            if debugingScan then print("All vendors processed for this store. Moving to the next store...") end
            if isScanning then processNextStore() end
        ]])
        if debugingScan then print("Persistent substring trigger created for vendor count detection.") end
    else
        if debugingScan then print("Vendor count trigger already exists.") end
    end
end

function setupVendScanAliases()
    -- Check if the alias group exists, if not, create it
    if exists("VendScan", "alias") == 0 then
        permGroup("VendScan", "alias")
        if debugingScan then print("Alias group 'VendScan' created.") end
    else
        if debugingScan then print("Alias group 'VendScan' already exists.") end
    end

    -- Add aliases with checks to prevent duplication

    -- Alias to start scanning
    if exists("viscan", "alias") == 0 then
        permAlias("viscan", "VendScan", "^viscan$", [[
            startScanning()
            print("Vendor scan started.")
        ]])
        if debugingScan then print("Alias 'viscan' created.") end
    else
        if debugingScan then print("Alias 'viscan' already exists.") end
    end

    -- Alias to display store inventory with optional parameter
-- Alias to display specific store inventory
    if exists("vivend", "alias") == 0 then
        permAlias("vivend", "VendScan", "^vivend (\\w+)$", [[
            local store = matches[2]
            if store and store ~= "" then
                display_store_inventory(store)
            else
                print("Error: Please specify a valid store name.")
            end
        ]])
        if debugingScan then print("Alias 'vivend' created.") end
    else
        if debugingScan then print("Alias 'vivend' already exists.") end
    end
    
    -- Alias to display all stores
    if exists("viall", "alias") == 0 then
        permAlias("viall", "VendScan", "^viall$", [[
            display_store_inventory()
        ]])
        if debugingScan then print("Alias 'viall' created.") end
    else
        if debugingScan then print("Alias 'viall' already exists.") end
    end

    -- Alias to display total needed minus count
    if exists("vitotal", "alias") == 0 then
        permAlias("vitotal", "VendScan", "^vitotal$", [[
            display_total_needed_minus_count()
        ]])
        if debugingScan then print("Alias 'vitotal' created.") end
    else
        if debugingScan then print("Alias 'vitotal' already exists.") end
    end

    -- Alias to toggle debugging
    if exists("videbug", "alias") == 0 then
        permAlias("videbug", "VendScan", "^videbug$", [[
            debugingScan = not debugingScan
            print("Debugging mode set to:", debugingScan and "ON" or "OFF")
        ]])
        if debugingScan then print("Alias 'videbug' created.") end
    else
        if debugingScan then print("Alias 'videbug' already exists.") end
    end

    -- Alias to manually refresh inventory (download JSON)
    if exists("vidownload", "alias") == 0 then
        permAlias("vidownload", "VendScan", "^vidownload$", [[
            manualRefreshInventory()
        ]])
        if debugingScan then print("Alias 'vidownload' created.") end
    else
        if debugingScan then print("Alias 'vidownload' already exists.") end
    end

    -- Alias to reset the scan process
    if exists("vireset", "alias") == 0 then
        permAlias("vireset", "VendScan", "^vireset$", [[
            resetScan()
        ]])
        if debugingScan then print("Alias 'vireset' created.") end
    else
        if debugingScan then print("Alias 'vireset' already exists.") end
    end

    -- Alias to show help for VendScan commands
    if exists("vihelp", "alias") == 0 then
        permAlias("vihelp", "VendScan", "^vihelp$", [[
            print("VendScan Alias Commands:")
            print("-----------------------------------------")
            print("viscan       - Start the scanning process.")
            print("vivend <store> - Show inventory for a specific store.")
            print("viall        - Display all items needed restocking")
            print("vitotal      - Display total needed items.")
            print("videbug      - Toggle debugging mode.")
            print("vidownload   - Manually download the latest inventory file.")
            print("vireset      - Reset the scanning process.")
            print("vihelp       - Show this help message.")
            print("")
            print("if you update the inventory file with new designs. you must delete the DynamicVendorTriggers")
            print("should automatically pick up once download is complete")
            print("-----------------------------------------")
        ]])
        if debugingScan then print("Alias 'vihelp' created.") end
    else
        if debugingScan then print("Alias 'vihelp' already exists.") end
    end

    print("VendScan aliases setup complete.")
end

scanStartup()
