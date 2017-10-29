unit semax;
//todo: add an dialog to the options to allow a user to manually set adjustements
//      for maximized height and position

{$mode delphi}{$H+}

interface

uses
  Classes, SysUtils,
  {$ifdef mswindows}Windows,{$endif}
  {$ifdef LCLCarbon}MacOSAll, CarbonPrivate, {$endif}
  LCLIntf,
  Forms, LazIDEIntf, SrcEditorIntf;

procedure Register;

implementation

type

  { THandler }

  THandler = class(TObject)
    class procedure OnWindowCreate(ASender: TObject);
    class procedure OnStateChange(ASender: TObject);
  end;

procedure Register;
begin
  SourceEditorManagerIntf.RegisterChangeEvent(semWindowCreate,  THandler.OnWindowCreate);
end;


function MainIDEBar: TForm;
var
  c: TComponent;
begin
  c:=LazarusIDE.GetMainBar;
  if Assigned(c) and (c is TForm) then Result:=TForm(c)
  else Result:=nil
end;

function GetMainBarWorkArea(var bnd: TRect): Boolean;
var
  f : Tform;
begin
  f:=MainIDEBar;
  if Assigned(f) then begin
    bnd:=f.Monitor.WorkareaRect;
    Result:=true;
  end else
    Result:=false;
end;

function GetMainBarBounds(var bnd: TRect): Boolean;
var
  f : TForm;
begin
  f:=MainIDEBar;
  Result:=Assigned(f);
  if not Result then Exit;
  {$ifdef mswindows}
  // no trust for LCL window height, since it
  // has to many special cases!
  windows.GetWindowRect(f.Handle, bnd);
  {$else}
  bnd:=f.BoundsRect;
  {$endif}
end;


procedure GetSourceEditorBounds(const mainBar, WorkArea: TRect; var Bnds: TRect);
begin
  // occupy all WorkArea, excluding the mainBar, that's presummed to be at the top!
  Bnds:=Classes.Rect( 0, mainBar.Bottom, WorkArea.Right, WorkArea.Bottom);
end;

{$ifdef mswindows}
type
  TWndProc = function (Window: HWnd; Msg: UInt; WParam: Windows.WParam; LParam: Windows.LParam): LResult; stdcall;
var
  PrevProc   : TWndProc = nil;
  hasDefault : Boolean = false;
  // these are initial values used by
  ofsY   : Integer = 0;
  ofsX   : Integer = 0;
  addW   : Integer = 0;
  {%H-}addTW  : Integer = 0;
  addH   : Integer = 0;
  {%H-}addTH  : Integer = 0;

function MinMaxProc(Window: HWnd; Msg: UInt; WParam: Windows.WParam; LParam: Windows.LParam): LResult; stdcall;
var
  info : PMINMAXINFO;
  bar  : TRect;
  wr   : TRect;
  b    : TRect;
begin
  Result:=Windows.CallWindowProc(PrevProc, Window, Msg, wParam, lParam);
  if Msg = WM_GETMINMAXINFO then begin
    info:=PMinMaxInfo(lParam);
    GetMainBarWorkArea(wr);
    if not hasDefault then begin
      ofsY := info^.ptMaxPosition.x;
      ofsX := info^.ptMaxPosition.y;
      addW := info^.ptMaxSize.x - Screen.Width;
      addH := info^.ptMaxSize.y - Screen.Height;
      addTH := info^.ptMaxTrackSize.y - Screen.Height;
      addTW := info^.ptMaxTrackSize.X - Screen.Width;
      hasDefault:=true;
    end;
    GetMainBarBounds(bar);
    GetSourceEditorBounds(bar, wr, b);
    // position
    info^.ptMaxPosition.x  := b.Left + ofsX;
    info^.ptMaxPosition.y  := b.Top  + ofsY;
    // size - horizontal
    info^.ptMaxSize.x      := b.Right - b.Left + AddW;
    info^.ptMaxTrackSize.x := b.Right - b.Left + AddW;
    // size - vertical
    info^.ptMaxSize.y      := b.Bottom - b.Top + AddH;
    info^.ptMaxTrackSize.y := b.Bottom - b.Top + AddH;
  end;
end;

procedure InstallProcHook(form: TForm);
begin
  if not Assigned(PrevProc) then
    PrevProc:=TWndProc(Windows.GetWindowLongPtr(form.Handle, GWL_WNDPROC)); //, PtrInt(@DestroyWindowProc));
  SetWindowLong(form.Handle, GWL_WNDPROC, PtrUInt(@MinMaxProc));
end;
{$endif}

{ THandler }

class procedure THandler.OnWindowCreate(ASender: TObject);
begin
  if not (ASender is TForm) then Exit;
  {$ifdef mswindows}
  InstallProcHook(TForm(ASender));
  {$else}
  TForm(ASender).OnWindowStateChange:=OnStateChange;
  {$endif}
end;

function GetOutterBounds(AForm: TForm; var bnd: TRect): Boolean;
{$ifdef LCLCarbon}
var
  wnd: WindowRef;
  mr : MacOSAll.Rect;
{$endif}
begin
  if not Assigned(AForm) then begin
    Result:=false;
    Exit;
  end;
  {$ifdef LCLCarbon}
  wnd:=HIViewGetWindow( TCarbonControl(AForm.Handle).Widget );
  GetWindowBounds(wnd, kWindowStructureRgn, mr);
  // kWindowStructureRgn = kWindowTitleBarRgn + kWindowGlobalPortRgn
  // kWindowStructureRgn - includes title and content (global port)
  bnd.Left:=mr.left;
  bnd.Top:=mr.top;
  bnd.Right:=mr.right;
  bnd.Bottom:=mr.bottom;
  {$else}
  Result:=GetWindowRect(AForm.Handle, bnd)>0;
  {$endif}
end;


procedure SetOutterBounds(AForm: TForm; const bnd: TRect);
{$ifdef LCLCarbon}
var
  wnd: WindowRef;
  mr : MacOSAll.Rect;
{$endif}
begin
  if not Assigned(AForm) then Exit;
  {$ifdef LCLCarbon}
  wnd:=HIViewGetWindow( TCarbonControl(AForm.Handle).Widget );
  mr.left:=bnd.Left;
  mr.top:=bnd.Top;
  mr.right:=bnd.Right;
  mr.bottom:=bnd.Bottom;
  SetWindowBounds(wnd, kWindowStructureRgn, mr);
  {$else}
  AForm.BoundsRect:=bnd;
  {$endif}
end;

class procedure THandler.OnStateChange(ASender: TObject);
var
  c   : TComponent;
  se  : TForm;
  bar : TForm;
  tp, h: Integer;
  wr   : TRect;
  hg   : Integer;
  rr   : TRect;
begin
  c:=TComponent(LazarusIDE.GetMainBar);
  if not (c is TForm) or not (ASender is TForm) then begin
    if assigned(C) then writeln (c.ClassName);
    Exit;
  end;

  bar := TForm(c);
  se := TForm(ASender);
  se.OnWindowStateChange := nil;

  if se.WindowState = wsMaximized then begin
    GetOutterBounds(bar, rr);
    h := rr.Bottom - rr.Top;
    tp := rr.Top + h;
    wr := se.Monitor.WorkareaRect;
    hg := wr.Bottom - wr.Top - tp;
    if se.Constraints.MaxHeight <> hg then begin
      se.Constraints.MaxHeight := hg;
      SetOutterBounds(se, bounds(wr.Left, tp, wr.Right - wr.Left, hg));
    end
  end else begin
    se.Constraints.MaxHeight := 0;
    se.Constraints.MaxWidth := 0;
  end;
  se.OnWindowStateChange := OnStatechange;
end;

end.

