-- FOLIO NCIP Connector ILLiad add-on
-- This add-on sends an NCIP message to FOLIO when a borrowing request is checked in to the receiving library.
-- FOLIO will create a set of associated instance, holding, and item records, suppress them,
-- and create a hold for the item in the specified user's account.

local settings = {};
settings.url = GetSetting("NCIP_URL");
settings.auth_key = GetSetting("NCIP_AUTH_KEY");

function Init()
    RegisterSystemEventHandler("BorrowingRequestCheckedInFromLibrary", "borrowing_check_in_item");
end

-- Function to handle the BorrowingRequestCheckedInFromLibrary event
function borrowing_check_in_item(args)
    local txNumber = args.TransactionNumber;

    if GetFieldValue("Transaction", "RequestType") == "Loan" then
        message_body = build_accept_item_xml();
	    local ncip_url = settings.url .. '/' .. settings.auth_key;
 	    make_post_request(ncip_url, message_body);
    end
end

-- Function to make a POST request to a FOLIO NCIP API
function make_post_request(address, message)
    luanet.load_assembly("System");
    luanet.load_assembly("System.Windows.Forms");
    local messageBox = luanet.import_type("System.Windows.Forms.MessageBox");
    local MessageBoxButtons = luanet.import_type("System.Windows.Forms.MessageBoxButtons");
    local MessageBoxIcon = luanet.import_type("System.Windows.Forms.MessageBoxIcon");

    local WebClient = luanet.import_type("System.Net.WebClient");
    if not WebClient then
    	error("Failed to import System.Net.WebClient");
    end
    local myWebClient = WebClient();
    if not myWebClient then
        error("Failed to initialize local WebClient");
    end
    myWebClient.Headers:Clear();
    myWebClient.Headers:Add("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/58.0.3029.110 Safari/537");
    myWebClient.Headers:Add("Content-Type", "application/xml; charset=UTF-8");

    local success, result = pcall(function()
        return myWebClient:UploadString(address, "POST", message)
    end);

    if success then
        local problem = find_problem(result);
        local message = "";
        if problem then
            message = "FOLIO reported a problem: " .. problem .. " (FOLIO records could not be created.)";
        else
            message = "FOLIO records created!";
        end
        messageBox.Show(message, "Alert", MessageBoxButtons.OK, MessageBoxIcon.Information);

        return result
    else
        message = "There was an error sending the request to FOLIO. Please check the logs for more information.";
        messageBox.Show(message, "Alert", MessageBoxButtons.OK, MessageBoxIcon.Information);

        local error_message;
        if type(result) == "table" then
            error_message = result.Message or "Unknown error";
            local inner_exception = result.InnerException;
            
            while inner_exception do
                error_message = error_message .. " | Inner exception: " .. (inner_exception.Message or "No further information");
                inner_exception = inner_exception.InnerException;
            end

            error_message = error_message .. " | StackTrace: " .. (result.StackTrace or "No stack trace available");
        else
            print(result.InnerException);
            error_message = tostring(result);
        end
        
        LogDebug("Detailed error message: " .. error_message);
        error("Request failed with message: " .. error_message);
    end
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
    -- NOTE: In ILLiad, the CitedPages field in the Transaction object has been overridden to provide the pickup location.
    -- If it becomes necessary to figure out where another field value is hiding, look up the Transaction database table
    -- fields in the Atlas ILLiad documentation, and maybe use Copilot or ChatGPT to quickly build Lua code to print out
    -- the values of every field in a request.
    local pickup_location = get_pickup_location(GetFieldValue('Transaction', 'CitedPages'));

    local xml = '<?xml version="1.0" encoding="UTF-8"?>';
    xml = xml .. '<NCIPMessage xmlns="http://www.niso.org/2008/ncip" version="http://www.niso.org/schemas/ncip/v2_02/ncip_v2_02.xsd">';
    xml = xml .. '<AcceptItem>';

    xml = xml .. '<InitiationHeader>';
    xml = xml .. '<FromAgencyId>';
    xml = xml .. '<AgencyId>ILL</AgencyId>';
    xml = xml .. '</FromAgencyId>';
    xml = xml .. '<ToAgencyId>';
    xml = xml .. '<AgencyId>Cornell</AgencyId>';
    xml = xml .. '</ToAgencyId>';
    xml = xml .. '<ApplicationProfileType>ILL</ApplicationProfileType>';
    xml = xml .. '</InitiationHeader>';

	xml = xml .. '<RequestId>';
    xml = xml .. '<AgencyId>Cornell</AgencyId>';
    xml = xml .. '<RequestIdentifierValue>' .. transaction_no .. '</RequestIdentifierValue>';
    xml = xml .. '</RequestId>';
    
    xml = xml .. '<RequestedActionType>Hold For Pickup And Notify</RequestedActionType>';
    
    xml = xml .. '<UserId>';
    xml = xml .. '<AgencyId>Cornell</AgencyId>';
    xml = xml .. '<UserIdentifierValue>' .. borrower .. '</UserIdentifierValue>';
    xml = xml .. '</UserId>';
    
    xml = xml .. '<ItemId>';
    xml = xml .. '<ItemIdentifierValue>' .. transaction_no  .. '</ItemIdentifierValue>';
    xml = xml .. '</ItemId>';
    
    xml = xml .. '<ItemOptionalFields>';
    xml = xml .. '<BibliographicDescription>';
    xml = xml .. '<Author>' .. author .. '</Author>';
    xml = xml .. '<Title>' .. title .. '</Title>';
    xml = xml .. '</BibliographicDescription>';
    xml = xml .. '</ItemOptionalFields>';

    xml = xml .. '<PickupLocation>' .. pickup_location .. '</PickupLocation>';
    xml = xml .. '</AcceptItem>';
    xml = xml .. '</NCIPMessage>';
    
    return xml;
end

-- Extract the problem detail from an XML response from FOLIO. This is used to display an error message to the user.
-- The actual response from FOLIO may be a 200 OK with a problem detail in the body, so we need to check for that.
-- This is a very simple parser that assumes the problem detail is the first element in the response. There are Lua-
-- specific XML parsers available, but this is a quick and dirty way to get the job done without trying to add libraries.
function find_problem(xml)
    local start_tag = "<ns1:ProblemDetail>";
    local end_tag = "</ns1:ProblemDetail>";
    local start_pos = xml:find(start_tag);
    local end_pos = xml:find(end_tag);

    if start_pos and end_pos then
        return xml:sub(start_pos + #start_tag, end_pos - 1);
    else
        return nil;
    end
end

-- Map the pickup location specified in the ILLiad request to a FOLIO location code.
function get_pickup_location()
    location = GetFieldValue('Transaction', 'CitedPages');

    if location == "Olin" then
        return "olin,circ";
    elseif location == "Africana" then
        return "afr,circ";
    elseif location == "Annex" then
        return "anx,grab";
    elseif location == "ILR" then
        return "ilr,circ";
    elseif location == "Fine" then
        return "fine,circ";
    elseif location == "Law" then
        return "law,circ";
    elseif location == "Management" then
        return "jgsm,circ";
    elseif location == "Mann" then
        return "mann,circ";
    elseif location == "Math" then
        return "math,circ";
    elseif location == "Music" then
        return "mus,circ";
    elseif location == "Nestle" then
        return "nest,circ";
    elseif location == "Tech" then
        return "remote,tech";
    elseif location == "Vet" then
        return "vet,circ";
    else
	    LogDebug("Didn't find a recognizable pickup location; defaulting to Olin. Location code found: " .. location);
        return "olin,circ";
    end
end
