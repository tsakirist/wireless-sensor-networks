COMPONENT=QueryAppC
BUILD_EXTRA_DEPS += SerialMsg.py
CLEAN_EXTRA = SerialMsg*
CFLAGS += -DTOSH_DATA_LENGTH=115

SerialMsg.py:
		mig python -target=null -python-classname=SerialMsg Serial.h SMsg -o $@
include $(MAKERULES)
