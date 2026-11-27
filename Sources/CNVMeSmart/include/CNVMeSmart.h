#ifndef CNVME_SMART_H
#define CNVME_SMART_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    bool available;
    uint8_t criticalWarning;
    uint8_t percentageUsed;
    uint8_t availableSpare;
    int32_t temperatureCelsius;
    uint64_t dataUnitsReadLow;
    uint64_t dataUnitsWrittenLow;
    uint64_t powerOnHours;
    uint64_t powerCycles;
} BaroNVMeSmartReading;

/// Pure read-only query of internal Apple NVMe S.M.A.R.T. health & TBW without root privileges.
bool baro_read_nvme_smart(BaroNVMeSmartReading *outReading);

#ifdef __cplusplus
}
#endif

#endif
