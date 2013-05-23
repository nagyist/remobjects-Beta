﻿namespace BetaServer;

interface

uses
  System.IO;

type
  Log = public class
  private
    class var fCount: Int32 := 0;
    class var fFilename: String := Path.ChangeExtension(typeOf(self).Assembly.Location, '.'+System.Environment.MachineName+'.log');
    const MAX_LOGFILE_SIZE = 1*1024*1024; { 1MB }
  protected
  public
    class method Log(aMessage: String); locked;
    class operator Explicit(aString: String): Log;
  end;
  
implementation

class method Log.Log(aMessage: String);
begin
  inc(fCount);
  if (fCount > 100) and (new FileInfo(fFilename).Length > MAX_LOGFILE_SIZE) then begin
    var lTemp := Path.ChangeExtension(fFilename, '.previous.log');
    if File.Exists(lTemp) then File.Delete(lTemp);
    File.Move(fFilename, lTemp);
    fCount := 0;
  end;

  File.AppendAllText(fFilename, DateTime.Now.ToString('yyyy-MM-dd HH:mm:ss')+' '+aMessage+#13#10);
  Console.WriteLine(aMessage);
end;

class operator Log.Explicit(aString: String): Log;
begin
  Log(aString);
end;

end.