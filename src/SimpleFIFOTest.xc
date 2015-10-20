/*
 * SimpleFIFOTest.xc
 *
 *  Created on: 20 Oct 2015
 *      Author: steve
 */
#include <stdio.h>
#include <print.h>
#include <xs1.h>
#include <platform.h>

/*
 * Define FIFO size (in 32-bit ints)
 */
#define bufSize 0x2000                      // MUST be a power of two, to permit logical-AND wraparounds
#define bufMask (bufSize-1)                 // MUST be one less than bufSize .. compile-time constant

/*
 * Change these parameters to cause different stress test conditions
 */
#define DEBUG_FIFO

#define highThroughput  (1)
#define producerSlow    (2)
#define oneFullBurst    (3)
#define makeOverflow    (4)

#define testType highThroughput

#if testType == highThroughput
#define producerStartupDelay_us 100
#define producerClkPeriod (10*100)                   // microseconds * 10ns XMOS timer period - tweak this for torture testing
#define producerBurstSize (5000000)
#define consumerReportingInterval 100000             // only print every n good receptions to the console
#define consumerStartupDelay_us 500
#define consumerInterDelay 0
#endif

#if testType == producerSlow                         // This checks that the consumer correctly busy-waits when empty fifo
#define producerStartupDelay_us 1000000
#define producerClkPeriod (100000*100)
#define producerBurstSize 50
#define consumerReportingInterval 1
#define consumerStartupDelay_us 0
#define consumerInterDelay 0
#endif

#if testType == oneFullBurst
#define producerStartupDelay_us 0
#define producerClkPeriod (10*100)
#define producerBurstSize bufSize                   // Fill 'em up!
#define consumerReportingInterval 256
#define consumerStartupDelay_us 1000000             // Wait, so it does get full
#define consumerInterDelay 0
#endif

#if testType == makeOverflow
#define producerStartupDelay_us 0
#define producerClkPeriod (10*100)
#define producerBurstSize (bufSize+1)               // Overflow!
#define consumerReportingInterval 256
#define consumerStartupDelay_us 1000000             // Wait, so it does get full
#define consumerInterDelay 0
#endif

timer t;
// Functions to get the time from a timer.
unsigned int get_time(void) {
    unsigned time;
    t :> time;
    return time;
}

/* ************************************************************************************
 * Producer and consumer tasks - these are just test scaffolding
 * ************************************************************************************/
timer t2;
void producer_task(streaming chanend cout)
{
    unsigned i=1, tick, j;

    delay_microseconds(producerStartupDelay_us);    // At very high throughputs, give printf()s a chance to get done before we start
    printf("Ready to send %d values ...\n", producerBurstSize);
    t2 :> tick;                                     // grab the current timer ref value
    for(j=0; j<producerBurstSize; j++) {
        select {
           case t2 when timerafter(tick) :> void:   // perform periodic task
             tick += producerClkPeriod;
             cout <: i++;
             break;
         }
    }
}

void consumer_task(chanend cin)
{
    unsigned v;
    char ct;
    unsigned vchk = 1;                              // Test scaffolding only
    unsigned T;                                     // ""
    unsigned consumed_ctr = 0;                      // ""

    delay_microseconds(consumerStartupDelay_us);    // Deliberately wait to show up buffering / overflow handling on slow consumers
    printf("Ready to consume - each dot is %d values read ...\n", consumerReportingInterval);
    T = get_time();
    while(1) {
        select {
          case inct_byref(cin, ct):
              // The other thread has notified us that data is ready
              // Signal that we wish to consume the data
              cin <: 0;
              cin :> v;                         // This should not block due to the case above

              // fixme: *** test code only:  check the values are expected, and print some stats
              consumed_ctr++;
              if((consumed_ctr % consumerReportingInterval) ==0) {
                  unsigned now = get_time();
                  printstr(".");                // progress ticker
                  T=now;
              }
              if(v == vchk) {
                  vchk++;                       // good - keep going
              }
              else {
                  printf("!!! Unexpected value %d consumed.  Resyncing.\n", v);
                  vchk = v + 1;                 // That's what we're expecting next
              }
              // fixme: *** end of test code
              break;
          // Could do other event-driven stuff in here
        }
#if consumerInterDelay != 0
        delay_microseconds(consumerInterDelay);                // fixme: test code only, Make the receiver slow, so the buffer fills
#endif
    }
}

/* ************************************************************************************
 * fifo_task - this is the unit under test, the part you need for actual applications
 * Consume values from c
 * Produce values out to a (non-streaming) channel through use of control tokens
 * ************************************************************************************/
void fifo_task(streaming chanend c, chanend d)
{
    unsigned bufHead = 0;                   // (head = tail) and (count = 0) when empty [likewise (head = tail) & (count = max) when full]
    unsigned bufTail = 0;
    unsigned bufCount = 0;                  // use separate count var as then we can use all entries in the ring buffer and correctly distinguish full/empty
    unsigned notified = 0;                  // Used for control-token passing
    unsigned buf[bufSize];                  // ring buffer

    while(1) {
        select {
          case c :> unsigned v:
            // Add new value to the buffer head
            if(bufCount < bufSize) {            // we have space
                buf[bufHead++] = v;
                bufHead &= bufMask;             // Cheap way to do wraparound
                bufCount++;
            }
#ifdef DEBUG_FIFO
            else {
                printstrln("*");                // fixme: Test code only:  Houston we have a problem, buffer overflow
            }
#endif
            if (!notified) {                    // Wake up the downstream consumer
              outct(d, XS1_CT_END);
              notified = 1;
            }
            break;

          case d :> int request:
            d <: buf[bufTail++];                // issue tail value to downstream channel
            bufTail &= bufMask;                 // Cheap way to do wraparound
            if(--bufCount==0) {
                notified = 0;                   // If buffer's empty we'll need to renotify later
            }
            else {
                outct(d, XS1_CT_END);
            }
            break;
        }
    }
}

int main(void)
{
    streaming chan c;
    chan d;

    // This version connects with a fifo task, thus:
    // producer -> fifo -> consumer
    par {
        producer_task(c);
        fifo_task(c, d);
        consumer_task(d);
    }
    return 0;
}
