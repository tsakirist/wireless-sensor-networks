COMPONENT = VmAppC
BUILD_EXTRA_DEPS += ApplicationMsg.py TerminateMsg.py
CLEAN_EXTRA = ApplicationMsg* TerminateMsg*
CFLAGS += -DTOSH_DATA_LENGTH=115

ApplicationMsg.py:
	mig python -target=null -python-classname=ApplicationMsg VmC.h app_msg -o $@

TerminateMsg.py:
	mig python -target=null -python-classname=TerminateMsg VmC.h serial_term_msg -o $@

include $(MAKERULES)
