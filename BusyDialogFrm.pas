unit BusyDialogFrm;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants,
  System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.Imaging.GIFImg, Vcl.ExtCtrls,
  SWMMIO, Vcl.StdCtrls;

type
  TBusyFrm = class(TForm)
    Label1: TLabel;
    Image1: TImage;
    procedure FormShow(Sender: TObject);

  private
    { Private declarations }
  public
    { Public declarations }
  end;

var
  BusyFrm: TBusyFrm;

implementation

{$R *.dfm}

procedure TBusyFrm.FormShow(Sender: TObject);
begin
  BusyFrm.color := clwhite;
end;

end.