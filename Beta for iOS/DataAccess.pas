﻿namespace Beta;

interface

uses
  Foundation;

type
  DataAccess = public class(INSXMLParserDelegate)
  private
    class var fSharedInstance: DataAccess;
    class method sharedInstance: DataAccess;

    var fUsername, fUserToken: NSString;
    fPushDeviceToken: NSData;
    method setPushDeviceToken(aValue: NSData);

    const API_URL = 'https://secure.remobjects.com/api/';
    const API_GETTOKEN = 'gettoken';
    const API_DOWNLAODS = 'downloads';
    const KEY_USERNAME = 'Username';
    const KEY_TOKEN = 'Token';
  
    {$REGION INSXMLParserDelegate}
    method parser(parser: NSXMLParser) didStartElement(elementName: NSString) namespaceURI(namespaceURI: NSString) qualifiedName(qName: NSString) attributes(attributeDict: NSDictionary);
    {$ENDREGION}

    method beginGetDataFromURL(aURL: NSURL) completion(aCompletion: block (aData: NSData; aResponse: NSHTTPURLResponse));

   protected
    method gotLoginGoken;
    method gotData;

    method beginRegisterForPush;
  public
    class property sharedInstance: DataAccess read sharedInstance;

    method init: id; override;

    property downloads: NSArray := new NSMutableArray;
    property pushDeviceToken: NSData read fPushDeviceToken write setPushDeviceToken;

    method beginLogin;
    method beginGetData;

    method beginLoginWithUsername(aUsername: String) password(aPassword: String) completion(aCompletion: block(aSUccess: Boolean));

    property delegate: IDataAccessDelegate;

    
    const NOTIFICATION_DOWNLOADS_CHANGED = 'com.remobjects.beta.downloads.changed';
  end;

  IDataAccessDelegate = public interface
    method askForLogin;
  end;

implementation

method DataAccess.init: id;
begin
  fUsername := NSUserDefaults.standardUserDefaults.objectForKey(KEY_USERNAME);
  fUserToken := NSUserDefaults.standardUserDefaults.objectForKey(KEY_TOKEN);
end;

class method DataAccess.sharedInstance: DataAccess;
begin
  if not assigned(fSharedInstance) then fSharedInstance := new DataAccess;
  result := fSharedInstance;
end;

method DataAccess.beginLogin;
begin
  if length(fUserToken) = 0 then delegate.askForLogin();
  
  if assigned(fUserToken) then begin
    gotLoginGoken();
    exit;
  end;

end;

method DataAccess.gotLoginGoken;
begin
  NSUserDefaults.standardUserDefaults.setObject(fUsername) forKey(KEY_USERNAME);  
  NSUserDefaults.standardUserDefaults.setObject(fUserToken) forKey(KEY_TOKEN); 
  NSUserDefaults.standardUserDefaults.synchronize();
  beginGetData();
end;

method DataAccess.beginGetDataFromURL(aURL: NSURL) completion(aCompletion: block(aData: NSData; aResponse: NSHTTPURLResponse));
begin
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), method begin

      var lRequest := NSURLRequest.requestWithURL(aURL) 
                                   cachePolicy(NSURLRequestReloadIgnoringLocalAndRemoteCacheData)
                                   timeoutInterval(30); 
      var lResponse: NSURLResponse;
      var lError: NSError;
      var lData := NSURLConnection.sendSynchronousRequest(lRequest) returningResponse(var lResponse) error(var lError); 

      // this is a hack; i need to encapsulate the HTTP GET better 
      if not assigned(lResponse) then
        lResponse := new NSHTTPURLResponse withURL(aURL) statusCode(501) HTTPVersion('1.1') headerFields(nil); 

      aCompletion(lData, lResponse as NSHTTPURLResponse);

    end);
end;

method DataAccess.beginGetData;
begin
  if length(fUserToken) = 0 then begin
    beginLogin();
    exit;
  end;

  var lURL := new NSURL withString(API_URL+API_DOWNLAODS+'?name=mh&token='+fUserToken);
  beginGetDataFromURL(lURL) completion(method (aData: NSData; aResponse: NSHTTPURLResponse) begin 

      case aResponse.statusCode of
        200: begin
            var lXml := new NSXMLParser withData(aData);
            if assigned(lXml) then begin
              NSLog('got xml data');
              lXml.delegate := self;
              lXml.parse();
              dispatch_async(dispatch_get_main_queue(), -> gotData());
            end 
            else begin
              NSLog('other error: %@', aResponse);
              // ToDo: indicate error?
            end;
          end;
        501: begin
            NSLog('bad login');
            fUserToken := nil;
            dispatch_async(dispatch_get_main_queue(), -> beginLogin());
          end;
        else begin
          NSLog('other error: %@', aResponse);
          // ToDo: indicate error?
        end;
      end;

    end);
end;

{$REGION INSXMLParserDelegate}
method DataAccess.parser(parser: NSXMLParser) didStartElement(elementName: NSString) namespaceURI(namespaceURI: NSString) qualifiedName(qName: NSString) attributes(attributeDict: NSDictionary);
begin
  if elementName = 'download' then begin
    //NSLog('got download: %@', attributeDict);
    var lDict := attributeDict.mutableCopy();

    var lDateFormatter := new NSDateFormatter;
    lDateFormatter.dateFormat := 'yyyy-MM-dd';
    NSLog('date: %@', lDict['date']);
    lDict['date'] := lDateFormatter.dateFromString(lDict['date']);

    NSMutableArray(downloads).addObject(lDict);
  end;
end;
{$ENDREGION}

method DataAccess.gotData;
begin
  NSNotificationCenter.defaultCenter.postNotificationName(NOTIFICATION_DOWNLOADS_CHANGED) object(self); 
end;

method DataAccess.beginLoginWithUsername(aUsername: String) password(aPassword: String) completion(aCompletion: block (aSUccess: Boolean));
begin
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), method begin

    fUsername := aUsername;
    
    var lError: NSError;
    fUserToken := new NSString withContentsOfURL(new NSURL withString(API_URL+API_GETTOKEN+'?name='+fUsername+'&password='+aPassword))
                               encoding(NSStringEncoding.NSUTF8StringEncoding)
                               error(var lError); 
    NSLog('error: %@', lError);
    if assigned(fUserToken) and not assigned(lError) and not fUserToken.hasPrefix('<') then begin
      NSLog('got token: %@', fUserToken);
      dispatch_async(dispatch_get_main_queue(), method begin
          aCompletion(true);
          gotLoginGoken();
        end);
    end
    else begin
      fUserToken := nil;
      dispatch_async(dispatch_get_main_queue(), method begin
          aCompletion(false);
        end);
    end;

  end);

end;

method DataAccess.beginRegisterForPush;
begin
  if not assigned(fUserToken) or not assigned(fPushDeviceToken) then exit; 

  {var p := new ApplePushProviderService_AsyncProxy withURL(new NSURL withString(URL));
  p.beginRegisterDevice(deviceToken, UIDevice.currentDevice.name) startWithBlock(method (aRequest: ROAsyncRequest) begin

      try
        p.endRegisterDevice(aRequest);
        NSLog('Registered with server');
      except
        on E: NSException do begin
          // doesnt catch!? why? Nougat bug?
          var lAlert := new UIAlertView withTitle('Failed to register with server') message(E.description) &delegate(nil) cancelButtonTitle('Cancel') otherButtonTitles(nil);
          lAlert.show();
        end;
      end;

    end);}
end;

method DataAccess.setPushDeviceToken(aValue: NSData);
begin
  fPushDeviceToken := aValue;
  beginRegisterForPush();
end;

end.
