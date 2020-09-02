unit modEqualizer;

interface

uses Math;

type EQState = record
  // Filter #1 (Low band)
  lf,f1p0,f1p1,f1p2,f1p3 : Double; //Frequency polse
  // Filter #2 (High band)
  hf,f2p0,f2p1,f2p2,f2p3 : Double; //Frequency polse
  // Sample history buffer
  sdm1,sdm2,sdm3 : Double;

  // Gain Controls
  lg,mg,hg : Double; //Gain
end;

const VSA = (1.0 / 4294967295.0); //Very small amount

procedure EQ_InitState(var ES : EQState; lowfreq,highfreq,mixfreq : Integer);
function EQ_Sample(var ES : EQState; Sample : Double) : Double;

implementation

procedure EQ_InitState(var ES : EQState; lowfreq,highfreq,mixfreq : Integer);
begin
  FillChar(ES,SizeOf(EQState),0);

  ES.lg := 1.0;
  ES.mg := 1.0;
  ES.hg := 1.0;

  ES.lf := 2 * sin(PI * (lowfreq / mixfreq));
  ES.hf := 2 * sin(PI * (highfreq / mixfreq));
end;

function EQ_Sample(var ES : EQState; Sample : Double) : Double;
var L,M,H : Double;
begin
  // Filter #2 (lowpass)

  es.f1p0 := es.f1p0 + (es.lf * (sample   - es.f1p0)) + vsa;
  es.f1p1 := es.f1p1 + (es.lf * (es.f1p0 - es.f1p1));
  es.f1p2 := es.f1p2 + (es.lf * (es.f1p1 - es.f1p2));
  es.f1p3 := es.f1p3 + (es.lf * (es.f1p2 - es.f1p3));

  l := es.f1p3;

  // Filter #2 (highpass)

  es.f2p0 := es.f2p0 + (es.hf * (sample   - es.f2p0)) + vsa;
  es.f2p1 := es.f2p1 + (es.hf * (es.f2p0 - es.f2p1));
  es.f2p2 := es.f2p2 + (es.hf * (es.f2p1 - es.f2p2));
  es.f2p3 := es.f2p3 + (es.hf * (es.f2p2 - es.f2p3));

  h := es.sdm3 - es.f2p3;

  // Calculate midrange (signal - (low + high))

  m := es.sdm3 - (h + l);

  // Scale, Combine and store

  l := l*es.lg;
  m := m*es.mg;
  h := h*es.hg;

  // Shuffle history buffer

  es.sdm3 := es.sdm2;
  es.sdm2 := es.sdm1;
  es.sdm1 := sample;

  // Return result

  Result := l + m + h;
end;

end.
 