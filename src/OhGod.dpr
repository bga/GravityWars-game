program OhGod;

uses
  Forms,
  Main in 'Main.pas' {frmMain},
  modDebug in 'modDebug.pas';

{$R *.res}

begin
  Application.Initialize;
  Application.Title := 'GravityWarz';
  Application.CreateForm(TfrmMain, frmMain);
  Application.Run;
end.
