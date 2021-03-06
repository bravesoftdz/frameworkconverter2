{ ------------------------------------------------------------------- }
{ Unit:    SWMMIO.pas }
{ Project: WERF Framework - SWMM Converter }
{ Version: 2.0 }
{ Date:    2/28/2014 }
{ Author:  Gesoyntec (D. Pankani) }
{ }
{ Delphi Pascal unit containing various utility functions, global variables }
{ and constants, primarily used for interacting with SWMM5 input / output }
{ files }
{ ------------------------------------------------------------------- }

unit SWMMIO;

interface

uses
  {Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
    ConverterErrors,
    StrUtils, Dialogs, jpeg, ExtCtrls, ComCtrls, StdCtrls, Buttons, DateUtils;}

  Windows, Messages, SysUtils, Variants, Classes, Graphics,
  ConverterErrors, StrUtils, DateUtils;

type
  TMTARecord = record // converted framework timeseries data structure
    tsName: string;
    tsNodeName: string;
    tsType: string; // FLOW or CONCEN
    tsUnitsFactor: Double; // default 1.0
    constituentSWMMName: string;
    constituentFWName: string;
    convFactor: Double; // default 1.0
    convertedTS: TStringList;
    convertedTSFilePath: string;
    ModelRunScenarioID: string;
    SWMMFilePath: string;
    scratchFilePath: string;
    mtaFilePath: string;
  end;

const
  //Development computer height - used to scale form resizing
  devComputerScreenHeight : integer = 768;
  // includes NsubcatchResults,SUBCATCH_RAINFALL,SUBCATCH_SNOWDEPTH,SUBCATCH_LOSSES,SUBCATCH_RUNOFF,SUBCATCH_GW_FLOW,SUBCATCH_GW_ELEV;
  NUMSUBCATCHVARS: integer = 7;
  // MIN_WQ_FLOW: Double = 0.001; // minmun water quality flow from swmm
  MIN_WQ_FLOW: Double = 0.00001;
  SWMMINPUTTOKENS: array [0 .. 6] of string = ('[DIVIDERS]', '[JUNCTIONS]',
    '[OUTFALLS]', '[STORAGE]', '[POLLUTANTS]', '[TIMESERIES]', '[INFLOWS]');

  // SWMM Node results types from enum NodeResultType in SWMM v5.022 enums.h
  // not all being used. Let here for future
  NODE_DEPTH: integer = 0; // not used - water depth above invert
  NODE_HEAD: integer = 1; // not used - hydraulic head
  NODE_VOLUME: integer = 2; // not used - volume stored & ponded
  NODE_LATFLOW: integer = 3; // not used - lateral inflow rate
  NODE_INFLOW: integer = 4; // *used - total inflow rate
  NODE_OVERFLOW: integer = 5; // not used - overflow rate
  NODE_QUAL: integer = 6; // not used - concentration of each pollutant

  MAX_NODE_RESULTS = 7;
  MAX_SUBCATCH_RESULTS = 7;
  MAX_LINK_RESULTS = 6;
  MAX_SYS_RESULTS = 14;
  opModes: array [0 .. 1] of string = ('SWMM_TO_FW', 'SWMM_FROM_FW');
  appTypes: array [0 .. 1] of string = ('SWMM_CONSOLE', 'SWMM_GUI');
  { constituentNames: array [0 .. 7] of string = ('FLOW', 'TSS', 'TP', 'DP',
    'DZn', 'TZN', 'DCU', 'TCU'); }
  constituentNames: array [0 .. 22] of string = ('Q', 'FC', 'TSS1', 'TSS2',
    'TSS3', 'TSS4', 'TSS5', 'TSS', 'TP', 'TDS', 'POO4', 'NO3', 'LDOM', 'RDOM',
    'LPOM', 'RPOM', 'BOD1', 'ALGAE', 'DO', 'TIC', 'ALK', 'Gen 1', 'NH4');
  // NnodeResults,NODE_DEPTH,NODE_HEAD,NODE_VOLUME,NODE_LATFLOW,NODE_INFLO,NODE_OVERFLOW;
  NUMNODEVARS: integer = 7;

  // NlinkResults,LINK_FLOW,LINK_DEPTH,LINK_VELOCITY,LINK_FROUDE,LINK_CAPACITY;
  NUMLINKVARS: integer = 6;

  // input/output file names
  // provides FW timespan and hold file paths for batching
  fileNameGroupNames = 'GroupNames.txt';

  fileNameParamsList = 'ParameterList.txt'; // number and list of constituents
  fileNameParamsMatch = 'ParameterMap.txt';
  // mapping of fw constituents to swmm
  fileNameScratch = 'Scratch'; // fw times series file
  fileNameFWControlFile = 'SwmmConvertStrings.txt';
  // fw times series control metatadata file
  fileNameMessages = 'Message.txt';
  // communicates successes and errors to framework

var
  workingDir: string; // exe folder
  SWMMFileStreamPosition: long;
  operatingMode: string; // SWMM_TO_FW or  SWMM_FROM_FW'
  appType: string; // SWMM_CONSOLE or SWMM_GUI
  // stores existing swmm TS and Inflow block names in swmm inputfile
  TSList, InflowsList: TStringList;
  PollList, NodeNameList: TStringList;
  frameCtrlFilePath, mtaFilePath: string;

function getSWMMNodeIDsFromTxtInput(swmmFileContentsList: TStringList)
  : TArray<TStringList>;
function getSWMMNodeIDsFromBinary(SWMMFilePath: string): TArray<TStringList>;
procedure Split(const Delimiter: Char; Input: string; const Strings: TStrings);
procedure saveTextFileToDisc(FileContentsList: TStringList; filePath: string;
  shdOverwrite: boolean = false);
function readLongTxtFile(filePath: string): TStringList;

implementation

uses FWIO;

function getSWMMNodeIDsFromTxtInput(swmmFileContentsList: TStringList)
  : TArray<TStringList>;
var
  // tempList: TStringList;
  rsltLists: TArray<TStringList>;
  SwmmTokens: TStringList;
  lineNumber, intTokenLoc, tempInt, i: integer;
  strLine, strToken, strObjectID, strStartDate, strEndDate: string;
begin
  intTokenLoc := 0;
  // tempList := TStringList.Create;
  // tempList.LoadFromFile(SWMMIO.workingDir + 'RockCreekDemoTest.inp');
  // tempList := readLongTxtFile(SWMMFilePath);
  // tempList.LoadFromFile(SWMMFilePath);

  SetLength(rsltLists, 5);
  for i := Low(rsltLists) to High(rsltLists) do
    rsltLists[i] := TStringList.Create;

  lineNumber := 0;
  while lineNumber < swmmFileContentsList.Count - 1 do
  begin
    strLine := LowerCase(swmmFileContentsList[lineNumber]);

    // save simulation and end dates start date - converts to lower case so search for lower case version
    tempInt := Pos('start_date', strLine);
    if (tempInt = 1) then
      strStartDate := Trim(ReplaceStr(strLine, 'start_date', '') )
    else
    begin
      tempInt := Pos('end_date', strLine);
    if (tempInt = 1) then
      strEndDate := Trim(ReplaceStr(strLine, 'end_date', ''));
    end;

    for i := 0 to High(SWMMINPUTTOKENS) do
    begin
      strToken := LowerCase(SWMMINPUTTOKENS[i]);
      intTokenLoc := Pos(strToken, strLine);

      // check inputfile line to see if token present
      if intTokenLoc > 0 then
        break;
    end;

    // if token found read in node names
    if intTokenLoc > 0 then
    begin
      Repeat
        inc(lineNumber);
        strLine := swmmFileContentsList[lineNumber];
        intTokenLoc := Pos('[', strLine);
        if intTokenLoc > 0 then
        begin
          dec(lineNumber);
          break;
        end;
        // ignore comment lines
        if (Pos(';;', strLine) < 1) and (Length(strLine) > 1) then
        begin
          // extract node name
          tempInt := Pos(' ', strLine);
          if tempInt > 0 then
          begin
            strObjectID := Copy(strLine, 1, tempInt - 1);
            // 0-NodeIDs list, 1-Pollutants list, 2-Timeseries list, 3-Inflows list
            if i = 4 then
            // if we are in the [POLLUTANTS] block save names to pollutants list
            begin
              rsltLists[1].Add(strObjectID);
            end
            else if i = 5 then
            // if we are in the [TIMESERIES] block save names to TIMESERIES list
            begin
              rsltLists[2].Add(strObjectID);
            end
            else if i = 6 then
            // if we are in the [INFLOWS] block save names to INFLOWS list
            begin
              rsltLists[3].Add(strLine);
            end
            else
              // everything else is a node so save names to nodes list
              rsltLists[0].Add(strObjectID);
          end;
        end;
      until intTokenLoc > 0;
    end;
    inc(lineNumber);
  end;
  rsltLists[4].Add(strStartDate);
  rsltLists[4].Add(strEndDate);
  result := rsltLists;
end;

function getSWMMNodeIDsFromBinary(SWMMFilePath: string): TArray<TStringList>;
var
  Stream: TFileStream;
  Reader: TBinaryReader;
  numberOfPeriods, outputStartPos: integer;
  numSubCatchs, numLinks, numPolls, numNodes: integer;
  reportStartDate, reportTimeInterv: Double;
  days: TDateTime;
  myYear, myMonth, myDay: Word;
  myHour, myMin, mySec, myMilli: Word;
  idx: long;
  numCharsInID: integer;
  tempID: string;
  tempIDCharArr: TArray<Char>;
  nodeIDList, pollutantIDList, miscList: TStringList;
  startDateList, endDateList: TStringList;
begin

  Stream := TFileStream.Create(SWMMFilePath, fmOpenRead or fmShareDenyWrite);
  nodeIDList := TStringList.Create();
  pollutantIDList := TStringList.Create();
  miscList := TStringList.Create();
  endDateList := TStringList.Create();
  startDateList := TStringList.Create();

  try
    Reader := TBinaryReader.Create(Stream);
    try

      // First get number of periods from the end of the file
      Stream.Seek(-4 * sizeof(integer), soEnd);

      // the byte position where the Computed Results section of the file begins (4-byte integer)
      outputStartPos := Reader.ReadInteger;

      // number of periods
      numberOfPeriods := Reader.ReadInteger;;

      Stream.Seek(0, soBeginning);

      Reader.ReadInteger; // Magic number
      Reader.ReadInteger; // SWMM Version number

      // Flow units - a code number for the flow units that are in effect where 0 = CFS, 1 = GPM, 2 = MGD, 3 = CMS, 4 = LPS, and 5 = LPD
      miscList.Add(IntToStr(Reader.ReadInteger)); // Flow units
      numSubCatchs := Reader.ReadInteger; // # subcatchments
      numNodes := Reader.ReadInteger; // # nodes
      numLinks := Reader.ReadInteger; // # links
      numPolls := Reader.ReadInteger; // # pollutants

      // Read all subcatchment IDs and discard, skipping this section is not straight forward since catchment
      // name lengths vary
      for idx := 0 to numSubCatchs - 1 do
      begin
        numCharsInID := Reader.ReadInteger;
        tempIDCharArr := Reader.ReadChars(numCharsInID);
      end;

      // Read all node IDs and save for use later
      for idx := 0 to numNodes - 1 do
      begin
        numCharsInID := Reader.ReadInteger;
        tempIDCharArr := Reader.ReadChars(numCharsInID);
        if Length(tempIDCharArr) > 0 then
        begin
          SetString(tempID, PChar(@tempIDCharArr[0]), Length(tempIDCharArr));
          nodeIDList.Add(tempID);
        end
      end;

      // Read all link IDs and discard, skipping this section is not straight forward since catchment
      // name lengths vary
      for idx := 0 to numLinks - 1 do
      begin
        numCharsInID := Reader.ReadInteger;
        tempIDCharArr := Reader.ReadChars(numCharsInID);
      end;

      // Read all pollutant IDs and save for use later
      for idx := 0 to numPolls - 1 do
      begin
        numCharsInID := Reader.ReadInteger;
        tempIDCharArr := Reader.ReadChars(numCharsInID);
        if Length(tempIDCharArr) > 0 then
        begin
          SetString(tempID, PChar(@tempIDCharArr[0]), Length(tempIDCharArr));
          pollutantIDList.Add(tempID);
        end
        else
      end;

      // save stream position for later when we extract node results to avoid having to start over
      SWMMFileStreamPosition := Stream.Position;

      // read pollutant units code
      miscList.Add(IntToStr(Reader.ReadInteger));

      Stream.Seek(outputStartPos - (sizeof(Double) + sizeof(integer)),
        soBeginning);

      // Get Start date and reporting timestep
      reportStartDate := Reader.ReadDouble;
      reportTimeInterv := Reader.ReadInteger;

      // compute timeseries start date
      days := reportStartDate;
      DecodeDateTime(days, myYear, myMonth, myDay, myHour, myMin,
        mySec, myMilli);
      startDateList.Add(IntToStr(myYear));
      startDateList.Add(IntToStr(myMonth));
      startDateList.Add(IntToStr(myDay));
      startDateList.Add(IntToStr(myHour));

      // compute timeseries end date
      days := reportStartDate + (reportTimeInterv * numberOfPeriods / 86400.0);
      DecodeDateTime(days, myYear, myMonth, myDay, myHour, myMin,
        mySec, myMilli);
      endDateList.Add(IntToStr(myYear));
      endDateList.Add(IntToStr(myMonth));
      endDateList.Add(IntToStr(myDay));
      endDateList.Add(IntToStr(myHour));

    finally
      Reader.free;
    end;
  finally
    Stream.free;
  end;
  SetLength(result, 5);
  result[0] := nodeIDList;
  result[1] := pollutantIDList;
  result[2] := startDateList;
  result[3] := endDateList;
  // miscellaneous variables list position 0-flow unit code, 1-pollutant conc unit code, 2-reporting timestep in seconds
  result[4] := miscList;
end;

procedure Split(const Delimiter: Char; Input: string; const Strings: TStrings);
begin
  Assert(Assigned(Strings));
  Strings.Clear;
  Strings.Delimiter := Delimiter;
  Strings.DelimitedText := '"' + StringReplace(Input, Delimiter,
    '"' + Delimiter + '"', [rfReplaceAll]) + '"';
end;

procedure saveTextFileToDisc(FileContentsList: TStringList; filePath: string;
  shdOverwrite: boolean = false);
var
  dirName: string;
begin
  // Save a new swmm file back to disc
  if ((FileContentsList <> nil) and (FileContentsList.Count > 0)) then
  begin
    // check if directory exists
    dirName := ExtractFilePath(filePath);
    if (DirectoryExists(dirName) = false) then
    begin
      if CreateDir(dirName) then
        // do nothing ShowMessage('New directory added OK')
      else
      begin
        raise Exception.Create
          ('Fatal Error: Unable to create directory for saving file - error : '
          + IntToStr(GetLastError));
        Exit;
      end;
    end;

    { First check if the file exists. }
    if (not shdOverwrite) and (FileExists(filePath)) then
      { If it exists, raise an exception. }
      raise Exception.Create
        ('Fatal Error: File already exists. Attempt to overwrite failed.')
    else
      FileContentsList.SaveToFile(filePath);
  end;
end;

function readLongTxtFile(filePath: string): TStringList;
var
  t: TextFile;
  s: TStringList;
  x: String;
begin
  s := TStringList.Create;
  AssignFile(t, filePath);
  Reset(t);
  while not eof(t) do
  begin
    Readln(t, x);
    s.Add(x);
  end;
  CloseFile(t);
  result := s;
end;

end.
