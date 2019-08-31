#!/usr/bin/perl

# instruction code mnemonics and arguments expected
%codes = (
          "ret" => "0 none none",
          "set" => "1 reg uint8",
          "cpy" => "2 reg reg",
          "add" => "3 reg reg",
          "sub" => "4 reg reg",
          "inc" => "5 reg none",
          "dec" => "6 reg none",
          "max" => "7 reg reg",
          "min" => "8 reg reg",
          "bgz" => "9 reg label",
          "bez" => "A reg label",
          "bra" => "B label none",
          "led" => "C bit none",
          "rdb" => "D reg none",
          "tmr" => "E uint8 none"
         );

# current line number
$lno = 0;

### check, print error message and exit
sub assert {
  ($_[0]) or die "line $lno: $_[1]\n";
}

### parse and return register number
sub getRegNr {
  my $lreg = 0 + substr($_[0],1,1);
  if ( (length($_[0]) !=  2) || (substr($_[0],0,1) ne "r")  || ($lreg < 1) || ($lreg > 6) ) {
    $lreg = 0; 
  }
  return($lreg);
}

### parse and return uint8 value
sub getUInt8 {
  my $lval = 0 + $_[0];
  if ( ($lval < 0) || ($lval > 255) ) {
    $lval = -1;
  }
  return($lval);
} 

### parse and return bit value
sub getBit {
  my $lval = 0 + $_[0];
  if ( ($lval != 0) && ($lval != 1) ) {
    $lval = -1;
  }
  return($lval);
}

### parse and emit code
sub codeGen {
  my ($file,$codelabel) = @_;
  my (@image,@labelRef,%labelPos);
  my ($line,$rest,$label,$mcode,$marg1,$marg2,$code,$arg1,$arg2);

  $line = "";
 
  while (<$file>) {
    $lno++;
    chomp(); 
    ($line,$rest) = split("\t");
    assert(($line eq $codelabel),"label '$codelabel' expected");
    assert(($rest eq ""),"more entries than expected");
    last;
  }

  if ($line eq "") { return(@image); }

  while (<$file>) {
    $lno++;
    chomp();
    ($label, $mcode, $marg1, $marg2, $rest) = split("\t"); 
    
    if ($label eq $codelabel) { last; }

    assert(($rest eq ""),"more entries than expected");
    assert(($label . $mcode . $marg1 . $marg2 ne ""),"unexpected empty line");
  
    assert((exists $codes{$mcode}),"unknown code '$mcode'"); 

    ($code, $arg1, $arg2) = split(" ",$codes{$mcode});
    if ($label ne "") {
      assert((!exists $labelPos{$label}),"duplicate label name '$label'");
      $labelPos{$label} = @image + 1;
    }

    # check first argument type and emit code

    if ($arg1 eq "none") {
      assert(($marg1 eq ""),"no first argument expected");
      push(@image,$code . "0");
    } 
    elsif ($arg1 eq "reg") { 
      $reg1 = getRegNr($marg1); 
      assert(($reg1 != 0),"first argument must be a valid register");
      push(@image,$code . $reg1);
    }  
    elsif ($arg1 eq "uint8") {
      $val1 = getUInt8($marg1);
      assert(($val1 != -1),"first argument must be an int [0..255]");
      push(@image,$code . "0");
      push(@image,sprintf("%02X",$val1)); 
    }
    elsif ($arg1 eq "label") {
      $label = $marg1;
      assert(($label ne "" ),"first argument must a label name");
      push(@image,$code . "0");
      push(@image,$label);
      push(@labelRef,$label . " " . @image);
    }  
    elsif ($arg1 eq "bit") {
      $val1 = getBit($marg1);
      assert(($val1 != -1),"first agument must a a bit value");
      push(@image,$code . $val1);
    }

   # check second argument type and emit code

    if ($arg2 eq "none") {
      assert(($marg2 eq ""),"no second argument expected");
    } 
    elsif ($arg2 eq "reg") { 
      $reg2 = getRegNr($marg2); 
      assert(($reg2 != 0),"second argument must be a valid register");
      push(@image,"0" . $reg2);
    }  
    elsif ($arg2 eq "uint8") {
      $val2 = getUInt8($marg2);
      assert(($val2 != -1),"second argument must be an int [0..255]");
      push(@image,sprintf("%02X",$val2));
    }
    elsif ($arg2 eq "label") {
      $label = $marg2;
      assert(($label ne "" ),"second argument must a label name");
      push(@image,$label);
      push(@labelRef,$label . " " . @image); 
    }

  }

  assert(($label eq $codelabel),"unexpected end of code segment");
  assert(($mode . $marg1 . $marg2 . $rest eq ""),"more entries than expected");
  
  # back-patch jumps

  for (my $i; $i < @labelRef; $i++) {
    my ($label, $pos) = split(" ",$labelRef[$i]); 
    assert((exists $labelPos{$label}),"undefined label name '$label'");
    my $lpos = $labelPos{$label};
    my $offset = $lpos - $pos;
    assert((($offset >= -127) && ($offset <= 127)),"label '$label' too far away");
    $label = sprintf("%02X",$offset);
    $label = substr($label,length($label)-2,2);
    $image[$pos-1] = $label;
  }

  return(@image);

}


### main

($ARGV[0] ne "") or die "usage: <inputfilename> <outputfilename>\n";
($ARGV[1] ne "") or die "usage: <inputfilename> <outputfilename>\n";

open (INPUT, "<" . $ARGV[0]) or die "cannot open $ARGV[0] for reading\n";

# produce code for init handler

@init = codeGen(\*INPUT,"--Init--");
(@init > 0) or die "no init handler code\n";
print "init code segment: @init\n";

# produce code for timer handler

@timer = codeGen(\*INPUT,"--Timer--");
print "timer code segment: @timer\n";

close (INPUT);

print "generating binary ... ";

# build metadata binary code

@metadata = (3+@init+@timer,0+@init,0+@timer);
$metabin = pack("c3",@metadata);

# build init handler binary code

$initstr = "";
for (my $i; $i < @init; $i++) {
  $initstr = $initstr . $init[$i];
}
$initbin = pack("H*",$initstr);

# build timer handler binary code

$timerstr = "";
for (my $i; $i < @timer; $i++) {
  $timerstr = $timerstr . $timer[$i];
}
$timerbin = pack("H*",$timerstr);

# write binary file

open (OUTPUT, ">" . $ARGV[1]) or die "cannot open $ARGV[1] for writing\n";
binmode(OUTPUT);
print OUTPUT $metabin;
print OUTPUT $initbin;
print OUTPUT $timerbin;
close(OUTPUT);

print "done: " . 0 + @metadata + @init + @timer . " bytes\n";

exit;
