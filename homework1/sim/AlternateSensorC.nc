/**
 * Simple sensor emulator that alternates its output 
 * between two constant values every <count> readings.
 *
 */

generic module AlternateSensorC(uint32_t val1, uint32_t val2,uint8_t count) { 
  provides interface Read<uint16_t>;
}
implementation
{
  uint32_t counter = 0;
  uint16_t cur_val = val1;
  
  task void senseResult() {
	  if(counter == count) {
		  counter = 0;
		  if(cur_val == val1){
			cur_val = val2;
		  } else {
			cur_val = val1;
		  }
	  }
	  counter++;
	  signal Read.readDone(SUCCESS, (uint16_t)cur_val);
  }

  command error_t Read.read() {
    return post senseResult();
  }
  
}