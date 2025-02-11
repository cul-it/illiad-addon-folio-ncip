-- Borrowing Check-In Logger Add-on
-- This add-on logs a message when a borrowing request is checked in from the library.

local settings = {};
settings.url = GetSetting("NCIP_URL");
settings.auth_key = GetSetting("NCIP_AUTH_KEY");
LogDebug("Retrieved auth_key: " .. tostring(settings.auth_key));

function Init()
    RegisterSystemEventHandler("BorrowingRequestCheckedInFromLibrary", "borrowing_check_in_item");
end

-- Function to handle the BorrowingRequestCheckedInFromLibrary event
function borrowing_check_in_item(args)
    local txNumber = args.TransactionNumber;
    LogDebug("Borrowing request checked in: " .. txNumber);
    
    if GetFieldValue("Transaction", "RequestType") == "Loan" then
        message_body = build_accept_item_xml();
        LogDebug("Message body: " .. message_body);
        LogDebug("About to start POST request");
        LogDebug("URL: " .. settings.url);
        LogDebug("secret: " .. settings.auth_key);
        LogDebug("Message: " .. message_body);

	    local ncip_url = settings.url .. '/' .. settings.auth_key;
 	    make_post_request(ncip_url, message_body)
    end
end

function make_post_request(address, data)
    luanet.load_assembly("System");

    local WebClient = luanet.import_type("System.Net.WebClient");
    if not WebClient then
    	error("Failed to import System.Net.WebClient")
    end
    local myWebClient = WebClient();
    if not myWebClient then
        error("Failed to initialize local WebClient")
    end
    myWebClient.Headers:Clear();
    myWebClient.Headers:Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537");
    myWebClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");

    local request_url = address
    local max_redirects = 5
      for i = 1, max_redirects do
        local success, result = pcall(function()
            return myWebClient:UploadString(request_url, "POST", data)
        end)

        if success then
	    LogDebug("Success! response: " .. result)
            return result  -- The response body you want
        else
	    LogDebug("Failure!")
            local error_message
            
            if type(result) == "table" then
                error_message = result.Message or "Unknown error"
                local inner_exception = result.InnerException
                
                while inner_exception do
                    error_message = error_message .. " | Inner exception: " .. (inner_exception.Message or "No further information")
                    inner_exception = inner_exception.InnerException
                end

                error_message = error_message .. " | StackTrace: " .. (result.StackTrace or "No stack trace available")
            else
     	        LogDebug("Plain old error message, no stack trace")
	        print(result.InnerException)
                error_message = tostring(result)
            end
            
            LogDebug("Detailed error message: " .. error_message)
            error("Request failed with message: " .. error_message)
        end
    end
    error("Too many redirects or errors")
end

-- Build the XML request string for the "AcceptItem" action
--
-- AcceptItem creates a set of associated instance, holding, and item records in FOLIO, suppresses them, and
-- creates a hold for the item in the specified user's account. The values we need to create the request are
-- taken from the Transaction object, which is apparently globally accessible.
function build_accept_item_xml()
    local transaction_no = GetFieldValue('Transaction', 'TransactionNumber');
    local author = GetFieldValue('Transaction', 'LoanAuthor');
    local title = GetFieldValue('Transaction', 'LoanTitle');
    local borrower = GetFieldValue('Transaction', 'Username');
    local pickup_location = GetFieldValue('Transaction', 'Location');

    LogDebug("mjc12: transaction pickup location: " .. GetFieldValue('Transaction', 'NVTGC'));
    LogDebug("mjc12: or this?" .. pickup_location);
    
    -- local xml = '';

    local xml = '<?xml version="1.0" encoding="UTF-8"?>';
    xml = xml .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">';
    xml = xml .. '<AcceptItem>';
    xml = xml .. '<InitiationHeader>';

    xml = xml .. '<FromAgencyId>';
    -- CHANGE THIS
    xml = xml .. '<AgencyId>' .. 'ILL' .. '</AgencyId>';
    xml = xml .. '</FromAgencyId>';

    xml = xml .. '<ToAgencyId>';
    -- CHANGE THIS
    xml = xml .. '<AgencyId>' .. 'Cornell' .. '</AgencyId>';
    xml = xml .. '</ToAgencyId>';

    -- CHANGE THIS
    xml = xml .. '<ApplicationProfileType>' .. 'ILL' .. '</ApplicationProfileType>';

    xml = xml .. '</InitiationHeader>';

	xml = xml .. '<RequestId>';
    -- CHANGE THIS
    xml = xml .. '<AgencyId>' .. 'Cornell' .. '</AgencyId>';

    xml = xml .. '<RequestIdentifierValue>' .. transaction_no .. '</RequestIdentifierValue>'
    xml = xml .. '</RequestId>';
    
    xml = xml .. '<RequestedActionType>Hold For Pickup And Notify</RequestedActionType>';
    
    xml = xml .. '<UserId>';
    -- CHANGE THIS
    xml = xml .. '<AgencyId>' .. 'Cornell' .. '</AgencyId>';
    -- xml = xml .. '<UserIdentifierType>Barcode Id</UserIdentifierType>';
    xml = xml .. '<UserIdentifierValue>' .. borrower .. '</UserIdentifierValue>';
    xml = xml .. '</UserId>';
    
    xml = xml .. '<ItemId>';
    xml = xml .. '<ItemIdentifierValue>' .. transaction_no  .. '</ItemIdentifierValue>';
    xml = xml .. '</ItemId>';
    
    -- RETURN DATE?
    -- PICKUP LOCATION?
    
    xml = xml .. '<ItemOptionalFields>';
    xml = xml .. '<BibliographicDescription>';
    xml = xml .. '<Author>' .. author .. '</Author>';
    xml = xml .. '<Title>' .. title .. '</Title>';
    xml = xml .. '</BibliographicDescription>';
    
    xml = xml .. '</ItemOptionalFields>';
    -- CHANGE THIS
    xml = xml .. '<PickupLocation>olin,circ</PickupLocation>';
    xml = xml .. '</AcceptItem>';
    xml = xml .. '</NCIPMessage>';
    
    return xml;
end