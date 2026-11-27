#include "CNVMeSmart.h"

#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/IOCFPlugIn.h>
#include <IOKit/IOKitLib.h>
#include <IOKit/storage/nvme/NVMeSMARTLibExternal.h>
#include <string.h>

static bool try_read_smart_from_service(io_service_t service, BaroNVMeSmartReading *out) {
    IOCFPlugInInterface **plugIn = NULL;
    SInt32 score = 0;

    kern_return_t kr = IOCreatePlugInInterfaceForService(
        service,
        kIONVMeSMARTUserClientTypeID,
        kIOCFPlugInInterfaceID,
        &plugIn,
        &score
    );
    if (kr != KERN_SUCCESS || plugIn == NULL) {
        return false;
    }

    IONVMeSMARTInterface **smart = NULL;
    HRESULT hr = (*plugIn)->QueryInterface(
        plugIn,
        CFUUIDGetUUIDBytes(kIONVMeSMARTInterfaceID),
        (LPVOID *)&smart
    );

    bool success = false;
    if (hr == S_OK && smart != NULL) {
        NVMeSMARTData data;
        memset(&data, 0, sizeof(data));
        IOReturn ret = (*smart)->SMARTReadData(smart, &data);
        if (ret == kIOReturnSuccess) {
            out->available = true;
            out->criticalWarning = data.CRITICAL_WARNING;
            out->percentageUsed = data.PERCENTAGE_USED;
            out->availableSpare = data.AVAILABLE_SPARE;

            int32_t kelvin = (int32_t)data.TEMPERATURE;
            if (kelvin > 200 && kelvin < 450) {
                out->temperatureCelsius = kelvin - 273;
            } else {
                out->temperatureCelsius = 0;
            }

            out->dataUnitsReadLow = data.DATA_UNITS_READ[0];
            out->dataUnitsWrittenLow = data.DATA_UNITS_WRITTEN[0];
            out->powerOnHours = data.POWER_ON_HOURS[0];
            out->powerCycles = data.POWER_CYCLES[0];
            success = true;
        }
        (*smart)->Release(smart);
    }

    IODestroyPlugInInterface(plugIn);
    return success;
}

static bool scan_matching_dict(CFMutableDictionaryRef matching, BaroNVMeSmartReading *out) {
    if (matching == NULL) {
        return false;
    }
    io_iterator_t iterator = 0;
    kern_return_t kr = IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator);
    if (kr != KERN_SUCCESS || iterator == 0) {
        return false;
    }

    bool found = false;
    io_service_t service = IOIteratorNext(iterator);
    while (service != 0) {
        if (!found && try_read_smart_from_service(service, out)) {
            found = true;
        }
        IOObjectRelease(service);
        if (found) {
            break;
        }
        service = IOIteratorNext(iterator);
    }

    IOObjectRelease(iterator);
    return found;
}

bool baro_read_nvme_smart(BaroNVMeSmartReading *outReading) {
    if (outReading == NULL) {
        return false;
    }
    memset(outReading, 0, sizeof(*outReading));

    if (scan_matching_dict(IOServiceMatching("IONVMeBlockStorageDevice"), outReading)) {
        return true;
    }
    if (scan_matching_dict(IOServiceMatching("IOEmbeddedNVMeBlockDevice"), outReading)) {
        return true;
    }

    CFMutableDictionaryRef propMatch = IOServiceMatching("IOService");
    if (propMatch != NULL) {
        CFDictionarySetValue(propMatch, CFSTR(kIOPropertyNVMeSMARTCapableKey), kCFBooleanTrue);
        if (scan_matching_dict(propMatch, outReading)) {
            return true;
        }
    }

    return false;
}
