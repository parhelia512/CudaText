(*
This Source Code Form is subject to the terms of the Mozilla Public
License, v. 2.0. If a copy of the MPL was not distributed with this
file, You can obtain one at http://mozilla.org/MPL/2.0/.

Copyright (c) Alexey Torgashin
*)

//{$define log_index}

unit form_menu_py;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics,
  ExtCtrls, Dialogs,
  ATSynEdit,
  ATSynEdit_Globals,
  ATSynEdit_Edits,
  ATStringProc,
  ATListbox,
  ATCanvasPrimitives,
  ATButtons,
  LclProc,
  LclType,
  LclIntf, Buttons,
  proc_globdata,
  proc_editor,
  proc_colors,
  proc_str,
  math;

type
  { TfmMenuApi }

  TfmMenuApi = class(TForm)
    ButtonCancel: TATButton;
    edit: TATEdit;
    list: TATListbox;
    PanelCaption: TPanel;
    procedure ButtonCancelClick(Sender: TObject);
    procedure editChange(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure FormShow(Sender: TObject);
    procedure listClick(Sender: TObject);
    procedure listDrawItem(Sender: TObject; C: TCanvas; AIndex: integer;
      const ARect: TRect);
  private
    { private declarations }
    FMultiline: boolean;
    listFiltered: TFPList;
    listFiltered_Simple: TFPList;
    listFiltered_Fuzzy: TFPList;
    FColorBg: TColor;
    FColorBgSel: TColor;
    FColorFont: TColor;
    FColorFontSel: TColor;
    FColorFontAlt: TColor;
    FColorFontHilite: TColor;
    procedure DoFilter;
    function GetResultCmd: integer;
    function IsFiltered(AOrigIndex: integer; out AWordMatch: boolean): boolean;
    procedure SetListCaption(const AValue: string);
  public
    { public declarations }
    listItems: TStringList;
    ResultCode: integer;
    InitItemIndex: integer;
    DisableFuzzy: boolean;
    DisableFullFilter: boolean;
    CollapseMode: TATCollapseStringMode;
    UseEditorFont: boolean;
    property Multiline: boolean read FMultiline write FMultiline;
    property ListCaption: string write SetListCaption;
  end;

implementation

{$R *.lfm}

{ TfmMenuApi }

procedure TfmMenuApi.FormShow(Sender: TObject);
var
  N: integer;
begin
  EditorCaretShapeFromString(edit.CaretShapeNormal, EditorOps.OpCaretViewNormal);
  EditorCaretShapeFromString(edit.CaretShapeOverwrite, EditorOps.OpCaretViewOverwrite);

  UpdateFormOnTop(Self);
  FixFormPositionToDesktop(Self, Screen.DesktopRect);

  if FMultiline then
    N:= 185
  else
    N:= 100;

  if UseEditorFont then
    //don't set list.ItemHeight, it don't work for multiline mode
    N:= Abs(N * EditorOps.OpFontSize div UiOps.VarFontSize);

  list.ItemHeightPercents:= N;

  DoFilter;

  if (edit.Text='') then
    List.ItemIndex:= InitItemIndex //IsIndexValid is checked in setter
  else
    List.ItemIndex:= listFiltered.IndexOf(Pointer(PtrInt(InitItemIndex))); //IsIndexValid is checked in setter

  ButtonCancel.Width:= ButtonCancel.Height;
end;

procedure TfmMenuApi.listClick(Sender: TObject);
var
  Pnt: TPoint;
  NIndex: integer;
begin
  Pnt:= list.ScreenToClient(Mouse.CursorPos);
  NIndex:= list.GetItemIndexAt(Pnt);
  if NIndex<0 then exit;
  ResultCode:= GetResultCmd;
  Close;
end;

procedure TfmMenuApi.FormCreate(Sender: TObject);
begin
  FColorBg:= GetAppColor(TAppThemeColor.ListBg);
  FColorBgSel:= GetAppColor(TAppThemeColor.ListSelBg);
  FColorFont:= GetAppColor(TAppThemeColor.ListFont);
  FColorFontSel:= GetAppColor(TAppThemeColor.ListSelFont);
  FColorFontAlt:= GetAppColor(TAppThemeColor.ListFontHotkey);
  FColorFontHilite:= GetAppColor(TAppThemeColor.ListFontHilite);

  if UiOps.ShowMenuDialogsWithBorder then
    BorderStyle:= bsDialog;

  edit.DoubleBuffered:= UiOps.DoubleBuffered;
  list.DoubleBuffered:= UiOps.DoubleBuffered;

  list.Color:= FColorBg;

  edit.Keymap:= AppKeymapMain;
  edit.Height:= ATEditorScale(UiOps.InputHeight);
  edit.Font.Name:= EditorOps.OpFontName;
  edit.Font.Size:= EditorOps.OpFontSize;
  edit.Font.Quality:= EditorOps.OpFontQuality;
  edit.Colors.TextFont:= GetAppColor(TAppThemeColor.OtherTextFont, TAppThemeColor.EdTextFont);
  edit.Colors.TextBG:= GetAppColor(TAppThemeColor.OtherTextBg, TAppThemeColor.EdTextBg);
  edit.Colors.TextSelFont:= GetAppColor(TAppThemeColor.EdSelFont);
  edit.Colors.TextSelBG:= GetAppColor(TAppThemeColor.EdSelBg);
  edit.Colors.BorderLine:= GetAppColor(TAppThemeColor.EdBorder);

  edit.OptCaretBlinkEnabled:= EditorOps.OpCaretBlinkEn;
  edit.OptCaretBlinkTime:= EditorOps.OpCaretBlinkTime;

  PanelCaption.Height:= ATEditorScale(26);
  PanelCaption.Font.Name:= UiOps.VarFontName;
  PanelCaption.Font.Size:= ATEditorScaleFont(UiOps.VarFontSize);
  PanelCaption.Font.Color:= FColorFont;

  self.Color:= FColorBg;
  self.Width:= ATEditorScale(UiOps.ListboxSizeX);
  self.Height:= ATEditorScale(UiOps.ListboxSizeY);

  ResultCode:= -1;
  listItems:= TStringlist.Create;
  listFiltered:= TFPList.Create;
  listFiltered_Simple:= TFPList.Create;
  listFiltered_Fuzzy:= TFPList.Create;
end;

procedure TfmMenuApi.editChange(Sender: TObject);
begin
  DoFilter;
end;

procedure TfmMenuApi.ButtonCancelClick(Sender: TObject);
begin
  ModalResult:= mrCancel;
end;

procedure TfmMenuApi.FormDestroy(Sender: TObject);
begin
  FreeAndNil(listFiltered_Fuzzy);
  FreeAndNil(listFiltered_Simple);
  FreeAndNil(listFiltered);
  FreeAndNil(listItems);
end;

procedure TfmMenuApi.FormKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if (key=VK_DOWN) or ((key=VK_J) and (Shift=[ssCtrl])) then
  begin
    if list.ItemIndex=list.ItemCount-1 then
      list.ItemIndex:= 0
    else
      list.ItemIndex:= list.ItemIndex+1;
    key:= 0;
    exit
  end;

  if (key=VK_UP) or ((key=VK_K) and (Shift=[ssCtrl])) then
  begin
    if list.ItemIndex=0 then
      list.ItemIndex:= list.ItemCount-1
    else
      list.ItemIndex:= list.ItemIndex-1;
    key:= 0;
    exit
  end;

  if (key=VK_HOME) and (Shift=[ssCtrl]) then
  begin
    list.ItemIndex:= 0;
    key:= 0;
    exit
  end;
  if (key=VK_END) and (Shift=[ssCtrl]) then
  begin
    list.ItemIndex:= list.ItemCount-1;
    key:= 0;
    exit
  end;

  if (key=VK_NEXT) and (Shift=[]) then
  begin
    list.ItemIndex:= Min(list.ItemCount-1, list.ItemIndex+list.VisibleItems);
    key:= 0;
    exit
  end;
  if (key=VK_PRIOR) and (Shift=[]) then
  begin
    list.ItemIndex:= Max(0, list.ItemIndex-list.VisibleItems);
    key:= 0;
    exit
  end;

  if key=VK_ESCAPE then
  begin
    Close;
    key:= 0;
    exit
  end;

  if key=VK_RETURN then
  begin
    if (list.ItemIndex>=0) and (list.ItemCount>0) then
    begin
      ResultCode:= GetResultCmd;
      Close;
    end;
    key:= 0;
    exit
  end;
end;

function TfmMenuApi.GetResultCmd: integer;
var
  n: integer;
begin
  n:= list.ItemIndex;
  if (n>=0) and (n<listFiltered.Count) then
    Result:= PtrInt(listFiltered[n])
  else
    Result:= -1;
end;

procedure TfmMenuApi.listDrawItem(Sender: TObject; C: TCanvas;
  AIndex: integer; const ARect: TRect);
const
  IndentFor1stLine = 4;
  IndentFor2ndLine = 10;
var
  WordResults: TAppSearchWordsResults;
  FuzzyResults: TATIntArray;
  buf, part_L, part_R: string;
  s_filter, s_name, s_name2, s_right: string;
  s_name_wide: UnicodeString;
  s_dots: string;
  cl: TColor;
  pnt: TPoint;
  RectClip: TRect;
  bCurrentFuzzy: boolean;
  bFound: boolean;
  nPosOfDots: integer;
  n, i: integer;
begin
  {$ifdef log_index}
  MsgLogToFilename(
    'listFiltered index: '+IntToStr(AIndex)+'; count: '+IntToStr(listFiltered.Count),
    AppDir_Settings+DirectorySeparator+'index.log',
    true);
  {$endif}

  //check indexes correctness, for issue #4277
  if (AIndex<0) or (AIndex>=listFiltered.Count) then exit;
  n:= PtrInt(listFiltered[AIndex]);

  {$ifdef log_index}
  MsgLogToFilename(
  'listItems index: '+IntToStr(AIndex)+'; count: '+IntToStr(listItems.Count),
    AppDir_Settings+DirectorySeparator+'index.log',
    true);
  {$endif}

  if (n<0) or (n>=listItems.Count) then exit;
  SSplitByChar(listItems[n], #9, part_L, part_R);

  {$ifdef log_index}
  MsgLogToFilename(
    'part_L: "'+part_L+'"; part_R: "'+part_R+'"',
    AppDir_Settings+DirectorySeparator+'index.log',
    true);
  {$endif}

  if UseEditorFont then
  begin
    c.Font.Name:= EditorOps.OpFontName;
    c.Font.Size:= ATEditorScaleFont(EditorOps.OpFontSize);
  end;

  if AIndex=list.ItemIndex then
  begin
    c.Font.Color:= FColorFontSel;
    cl:= FColorBgSel;
  end
  else
  begin
    c.Font.Color:= FColorFont;
    cl:= FColorBg;
  end;
  c.Brush.Color:= cl;
  c.Pen.Color:= cl;
  c.FillRect(ARect);

  if not FMultiline then
  begin
    //right part
    n:= ARect.Width div 2;
    s_right:= CanvasCollapseStringByDots(C, part_R, acsmLeft, n);

    //left part
    //less space for name if part_R long
    n:= ARect.Width - C.TextWidth(s_right) - 2*IndentFor1stLine;
    s_name:= part_L;
    s_name2:= CanvasCollapseStringByDots(C, part_L, CollapseMode, n);
  end
  else
  begin
    n:= ARect.Width;

    //right part
    s_right:= CanvasCollapseStringByDots(C, part_R, CollapseMode, n - IndentFor2ndLine);

    //left part
    s_name:= part_L;
    s_name2:= CanvasCollapseStringByDots(C, part_L, CollapseMode, n - IndentFor1stLine);
  end;

  s_name_wide:= Utf8Decode(s_name);
  s_filter:= Trim(Utf8Encode(edit.Text));

  if CollapseMode<>acsmNone then
  begin
    s_dots:= UTF8Encode(UnicodeString(#$2026));
    nPosOfDots:= Pos(s_dots, s_name2);
  end
  else
    nPosOfDots:= 0;

  bCurrentFuzzy:= UiOps.ListboxFuzzySearch and not DisableFuzzy;
  if bCurrentFuzzy and (s_name<>s_name2) then
    bCurrentFuzzy:= false;

  pnt.x:= ARect.Left+IndentFor1stLine;
  pnt.y:= ARect.Top+1;
  c.TextOut(pnt.x, pnt.y, s_name2);

  c.Font.Color:= FColorFontHilite;

  bFound:= STextListsFuzzyInput(
             s_name,
             s_filter,
             WordResults,
             FuzzyResults,
             bCurrentFuzzy);

  if bFound then
  begin
    if Length(FuzzyResults)>0 then
    begin
      for i:= Low(FuzzyResults) to High(FuzzyResults) do
      begin
        if (nPosOfDots>0) and (FuzzyResults[i]>nPosOfDots) then
          Break;
        buf:= Utf8Encode(UnicodeString(s_name_wide[FuzzyResults[i]]));
        n:= c.TextWidth(Utf8Encode(Copy(s_name_wide, 1, FuzzyResults[i]-1)));
        RectClip:= Rect(
          pnt.x+n,
          pnt.y,
          pnt.x+n+c.TextWidth(buf),
          ARect.Bottom
          );
        ExtTextOut(c.Handle,
          RectClip.Left,
          RectClip.Top,
          ETO_CLIPPED+ETO_OPAQUE,
          @RectClip,
          PChar(buf),
          Length(buf),
          nil
          );
      end;
    end
    else
    if WordResults.MatchesCount>0 then
    begin
      for i:= 0 to WordResults.MatchesCount-1 do
      begin
        if (nPosOfDots>0) and (WordResults.MatchesArray[i].WordPos+WordResults.MatchesArray[i].WordLen>nPosOfDots) then
          Break;
        buf:= Copy(s_name, WordResults.MatchesArray[i].WordPos, WordResults.MatchesArray[i].WordLen);
        n:= c.TextWidth(Copy(s_name, 1, WordResults.MatchesArray[i].WordPos-1));
        RectClip:= Rect(
          pnt.x+n,
          pnt.y,
          pnt.x+n+c.TextWidth(buf),
          ARect.Bottom
          );
        ExtTextOut(c.Handle,
          RectClip.Left,
          RectClip.Top,
          ETO_CLIPPED+ETO_OPAQUE,
          @RectClip,
          PChar(buf),
          Length(buf),
          nil
          );
      end;
    end;
  end;

  if s_right<>'' then
  begin
    if not FMultiline then
    begin
      pnt.x:= ARect.Right-IndentFor1stLine-c.TextWidth(s_right) + 2;
      //right part is painted over left part, so clear the space
      c.FillRect(pnt.x, pnt.y, ARect.Right, pnt.y+list.ItemHeight-1);
    end
    else
    begin
      pnt.x:= ARect.Left+IndentFor2ndLine;
      Inc(pnt.y, list.ItemHeight div 2);
    end;

    c.Font.Color:= FColorFontAlt;
    c.TextOut(pnt.x, pnt.y, s_right);
  end;
end;

procedure TfmMenuApi.DoFilter;
var
  bSimple: boolean;
  i: integer;
begin
  listFiltered.Clear;
  listFiltered_Simple.Clear;
  listFiltered_Fuzzy.Clear;

  for i:= 0 to listItems.Count-1 do
    if IsFiltered(i, bSimple) then
    begin
      if bSimple then
        listFiltered_Simple.Add(Pointer(PtrInt(i)))
      else
        listFiltered_Fuzzy.Add(Pointer(PtrInt(i)));
    end;

  listFiltered.AddList(listFiltered_Simple);
  listFiltered.AddList(listFiltered_Fuzzy);

  list.ItemIndex:= 0;
  list.ItemTop:= 0;
  list.VirtualItemCount:= listFiltered.Count;
  list.Invalidate;
end;

function TfmMenuApi.IsFiltered(AOrigIndex: integer; out AWordMatch: boolean): boolean;
var
  WordResults: TAppSearchWordsResults;
  FuzzyResults: TATIntArray;
  SFind, SText: string;
begin
  Result:= false;
  AWordMatch:= false;

  SFind:= Trim(UTF8Encode(edit.Text));
  if SFind='' then
    exit(true);

  if (AOrigIndex<0) or (AOrigIndex>=listItems.Count) then
    exit;
  SText:= listItems[AOrigIndex];
  if DisableFullFilter then
    SText:= SGetItem(SText, #9);

  Result:= STextListsFuzzyInput(
             SText,
             SFind,
             WordResults,
             FuzzyResults,
             UiOps.ListboxFuzzySearch and not DisableFuzzy);
  AWordMatch:= WordResults.MatchesCount>0;
end;

procedure TfmMenuApi.SetListCaption(const AValue: string);
begin
  if UiOps.ShowMenuDialogsWithBorder then
  begin
    Caption:= AValue;
    PanelCaption.Hide;
  end
  else
  begin
    PanelCaption.Caption:= AValue;
    PanelCaption.Visible:= AValue<>'';
  end;
end;

end.
