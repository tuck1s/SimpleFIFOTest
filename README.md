XMOS fifo task, with test harness comprising producer and consumer tasks for torture tests.

Change the value of const unsigned clkPeriod = 10*100; to adjust the rate the producer task runs.

You can also change
- the startup delay of the producer task (it's necessary to have *some* delay, to allow the initial console printing to get out)
- The reporting interval of the consumer task (which just prints a single '.' to not waste too much time on console activity)
- The startup delay (if any) of the consumer task (to simulate sleepy consumers)
- Make the receiver slow, so the buffer fills

On a StartKit I found stable running around 10us sending interval; much below this and the '.' progress marker kicks the fifo into 
buffer overflow, which prints a '*' warning, which causes slowness, which causes overrun etc.

Without all the debug code etc. you could probably run faster & harder.

Added the following test cases:
- highThroughput
- producerSlow
- oneFullBurst
- makeOverflow  

These are explained further in the source comments.
