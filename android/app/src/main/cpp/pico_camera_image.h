// PICO XR_PICO_camera_image extension declarations, isolated from Khronos headers.
// Derived from the public OpenXR header in madderscientist/PicoBridge
// (OpenXR header under Apache-2.0); compare against PICO Native SDK 3.0.0.
// Only included if Khronos' installed header does not expose this extension.
#pragma once
#include <openxr/openxr.h>

#ifndef XR_PICO_camera_image
#define XR_TYPE_AVAILABLE_CAMERAS_ENUMERATE_INFO_PICO static_cast<XrStructureType>(1010033000)
#define XR_TYPE_CAMERA_PROPERTIES_GET_INFO_PICO static_cast<XrStructureType>(1010033001)
#define XR_TYPE_CAMERA_PROPERTIES_PICO static_cast<XrStructureType>(1010033002)
#define XR_TYPE_CAMERA_PROPERTY_FACING_PICO static_cast<XrStructureType>(1010033003)
#define XR_TYPE_CAMERA_PROPERTY_POSITION_PICO static_cast<XrStructureType>(1010033004)
#define XR_TYPE_CAMERA_PROPERTY_CAMERA_TYPE_PICO static_cast<XrStructureType>(1010033005)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITIES_GET_INFO_PICO static_cast<XrStructureType>(1010033006)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITIES_PICO static_cast<XrStructureType>(1010033007)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITY_IMAGE_RESOLUTION_PICO static_cast<XrStructureType>(1010033008)
#define XR_TYPE_CAMERA_CAPABILITY_IMAGE_RESOLUTION_PICO static_cast<XrStructureType>(1010033009)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITY_DATA_TRANSFER_TYPE_PICO static_cast<XrStructureType>(1010033010)
#define XR_TYPE_CAMERA_CAPABILITY_DATA_TRANSFER_TYPE_PICO static_cast<XrStructureType>(1010033011)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITY_IMAGE_FORMAT_PICO static_cast<XrStructureType>(1010033012)
#define XR_TYPE_CAMERA_CAPABILITY_IMAGE_FORMAT_PICO static_cast<XrStructureType>(1010033013)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITY_CAMERA_MODEL_PICO static_cast<XrStructureType>(1010033014)
#define XR_TYPE_CAMERA_CAPABILITY_CAMERA_MODEL_PICO static_cast<XrStructureType>(1010033015)
#define XR_TYPE_CAMERA_SUPPORTED_CAPABILITY_IMAGE_FPS_PICO static_cast<XrStructureType>(1010033016)
#define XR_TYPE_CAMERA_CAPABILITY_IMAGE_FPS_PICO static_cast<XrStructureType>(1010033017)
#define XR_TYPE_CAMERA_DEVICE_CREATE_INFO_PICO static_cast<XrStructureType>(1010033018)
#define XR_TYPE_CREATE_CAMERA_DEVICE_COMPLETION_PICO static_cast<XrStructureType>(1010033019)
#define XR_TYPE_CAMERA_CAPTURE_SESSION_CREATE_INFO_PICO static_cast<XrStructureType>(1010033020)
#define XR_TYPE_CREATE_CAMERA_CAPTURE_SESSION_COMPLETION_PICO static_cast<XrStructureType>(1010033021)
#define XR_TYPE_CAMERA_INTRINSICS_PICO static_cast<XrStructureType>(1010033022)
#define XR_TYPE_CAMERA_EXTRINSICS_PICO static_cast<XrStructureType>(1010033023)
#define XR_TYPE_CAMERA_CAPTURE_BEGIN_INFO_PICO static_cast<XrStructureType>(1010033024)
#define XR_TYPE_CAMERA_IMAGE_ACQUIRE_INFO_PICO static_cast<XrStructureType>(1010033025)
#define XR_TYPE_CAMERA_IMAGE_PICO static_cast<XrStructureType>(1010033026)
#define XR_TYPE_CAMERA_IMAGE_DATA_RAW_BUFFER_PICO static_cast<XrStructureType>(1010033027)
#define XR_TYPE_CAMERA_CAPABILITIES_PICO static_cast<XrStructureType>(1010033028)
#define XR_CAMERA_IMAGE_NO_UPDATE_PICO static_cast<XrResult>(1010033000)
#define XR_ERROR_CAMERA_UNAVAILABLE_PICO static_cast<XrResult>(-1010033000)
#define XR_ERROR_CAMERA_OCCUPIED_PICO static_cast<XrResult>(-1010033001)
#define XR_ERROR_CAMERA_CAPTURE_SESSION_NOT_CAPTURING_PICO static_cast<XrResult>(-1010033003)

#define XR_PICO_camera_image 1
XR_DEFINE_ATOM(XrCameraIdPICO)
XR_DEFINE_ATOM(XrCameraImageIdPICO)
XR_DEFINE_HANDLE(XrCameraDevicePICO)
XR_DEFINE_HANDLE(XrCameraCaptureSessionPICO)
#define XR_PICO_camera_image_SPEC_VERSION 1
#define XR_PICO_CAMERA_IMAGE_EXTENSION_NAME "XR_PICO_camera_image"

typedef enum XrCameraPropertyTypePICO {
    XR_CAMERA_PROPERTY_TYPE_FACING_PICO = 1,
    XR_CAMERA_PROPERTY_TYPE_POSITION_PICO = 2,
    XR_CAMERA_PROPERTY_TYPE_CAMERA_TYPE_PICO = 3,
    XR_CAMERA_PROPERTY_TYPE_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraPropertyTypePICO;

typedef enum XrCameraFacingPICO {
    XR_CAMERA_FACING_WORLD_PICO = 1,
    XR_CAMERA_FACING_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraFacingPICO;

typedef enum XrCameraPositionPICO {
    XR_CAMERA_POSITION_UNSPECIFIED_PICO = 1,
    XR_CAMERA_POSITION_LEFT_PICO = 2,
    XR_CAMERA_POSITION_RIGHT_PICO = 3,
    XR_CAMERA_POSITION_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraPositionPICO;

typedef enum XrCameraTypePICO {
    XR_CAMERA_TYPE_PASSTHROUGH_COLOR_PICO = 1,
    XR_CAMERA_TYPE_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraTypePICO;

typedef enum XrCameraCapabilityTypePICO {
    XR_CAMERA_CAPABILITY_TYPE_IMAGE_RESOLUTION_PICO = 1,
    XR_CAMERA_CAPABILITY_TYPE_IMAGE_FORMAT_PICO = 2,
    XR_CAMERA_CAPABILITY_TYPE_DATA_TRANSFER_TYPE_PICO = 3,
    XR_CAMERA_CAPABILITY_TYPE_CAMERA_MODEL_PICO = 4,
    XR_CAMERA_CAPABILITY_TYPE_IMAGE_FPS_PICO = 5,
    XR_CAMERA_CAPABILITY_TYPE_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraCapabilityTypePICO;

typedef enum XrCameraDataTransferTypePICO {
    XR_CAMERA_DATA_TRANSFER_TYPE_RAW_BUFFER_PICO = 1,
    XR_CAMERA_DATA_TRANSFER_TYPE_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraDataTransferTypePICO;

typedef enum XrCameraImageFormatPICO {
    XR_CAMERA_IMAGE_FORMAT_RGBA_8888_PICO = 1,
    XR_CAMERA_IMAGE_FORMAT_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraImageFormatPICO;

typedef enum XrCameraModelPICO {
    XR_CAMERA_MODEL_PINHOLE_PICO = 1,
    XR_CAMERA_MODEL_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraModelPICO;

typedef enum XrCameraImageFpsPICO {
    XR_CAMERA_IMAGE_FPS_30_PICO = 1,
    XR_CAMERA_IMAGE_FPS_60_PICO = 2,
    XR_CAMERA_IMAGE_FPS_MAX_ENUM_PICO = 0x7FFFFFFF
} XrCameraImageFpsPICO;
typedef struct XR_MAY_ALIAS XrCameraPropertyBaseHeaderPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
} XrCameraPropertyBaseHeaderPICO;

typedef struct XrCameraPropertiesPICO {
    XrStructureType                     type;
    const void* XR_MAY_ALIAS            next;
    uint32_t                            propertyCount;
    XrCameraPropertyBaseHeaderPICO**    properties;
} XrCameraPropertiesPICO;

typedef struct XR_MAY_ALIAS XrCameraCapabilityBaseHeaderPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
} XrCameraCapabilityBaseHeaderPICO;

typedef struct XrCameraCapabilitiesPICO {
    XrStructureType                       type;
    const void* XR_MAY_ALIAS              next;
    uint32_t                              capabilityCount;
    XrCameraCapabilityBaseHeaderPICO**    capabilities;
} XrCameraCapabilitiesPICO;

typedef struct XrAvailableCamerasEnumerateInfoPICO {
    XrStructureType                    type;
    const void* XR_MAY_ALIAS           next;
    const XrCameraPropertiesPICO*      properties;
    const XrCameraCapabilitiesPICO*    capabilities;
} XrAvailableCamerasEnumerateInfoPICO;

typedef struct XrCameraPropertiesGetInfoPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraIdPICO              cameraId;
} XrCameraPropertiesGetInfoPICO;

typedef struct XrCameraPropertyFacingPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraFacingPICO          facing;
} XrCameraPropertyFacingPICO;

typedef struct XrCameraPropertyPositionPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraPositionPICO        position;
} XrCameraPropertyPositionPICO;

typedef struct XrCameraPropertyCameraTypePICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraTypePICO            cameraType;
} XrCameraPropertyCameraTypePICO;

typedef struct XrCameraSupportedCapabilitiesGetInfoPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraIdPICO              id;
} XrCameraSupportedCapabilitiesGetInfoPICO;

typedef struct XR_MAY_ALIAS XrCameraSupportedCapabilityBaseHeaderPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
} XrCameraSupportedCapabilityBaseHeaderPICO;

typedef struct XrCameraSupportedCapabilitiesPICO {
    XrStructureType                                type;
    const void* XR_MAY_ALIAS                       next;
    uint32_t                                       capabilityCount;
    XrCameraSupportedCapabilityBaseHeaderPICO**    capabilities;
} XrCameraSupportedCapabilitiesPICO;

typedef struct XrCameraSupportedCapabilityImageResolutionPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    uint32_t                    resolutionCapacityInput;
    uint32_t                    resolutionCountOutput;
    XrExtent2Di*                resolutions;
} XrCameraSupportedCapabilityImageResolutionPICO;

typedef struct XrCameraCapabilityImageResolutionPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrExtent2Di                 resolution;
} XrCameraCapabilityImageResolutionPICO;

typedef struct XrCameraSupportedCapabilityDataTransferTypePICO {
    XrStructureType                  type;
    const void* XR_MAY_ALIAS         next;
    uint32_t                         typeCapacityInput;
    uint32_t                         typeCountOutput;
    XrCameraDataTransferTypePICO*    types;
} XrCameraSupportedCapabilityDataTransferTypePICO;

typedef struct XrCameraCapabilityDataTransferTypePICO {
    XrStructureType                 type;
    const void* XR_MAY_ALIAS        next;
    XrCameraDataTransferTypePICO    transferType;
} XrCameraCapabilityDataTransferTypePICO;

typedef struct XrCameraSupportedCapabilityImageFormatPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    uint32_t                    formatCapacityInput;
    uint32_t                    formatCountOutput;
    XrCameraImageFormatPICO*    formats;
} XrCameraSupportedCapabilityImageFormatPICO;

typedef struct XrCameraCapabilityImageFormatPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraImageFormatPICO     format;
} XrCameraCapabilityImageFormatPICO;

typedef struct XrCameraSupportedCapabilityCameraModelPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    uint32_t                    modelCapacityInput;
    uint32_t                    modelCountOutput;
    XrCameraModelPICO*          models;
} XrCameraSupportedCapabilityCameraModelPICO;

typedef struct XrCameraCapabilityCameraModelPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraModelPICO           model;
} XrCameraCapabilityCameraModelPICO;

typedef struct XrCameraSupportedCapabilityImageFpsPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    uint32_t                    fpsCapacityInput;
    uint32_t                    fpsCountOutput;
    XrCameraImageFpsPICO*       fps;
} XrCameraSupportedCapabilityImageFpsPICO;

typedef struct XrCameraCapabilityImageFpsPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraImageFpsPICO        fps;
} XrCameraCapabilityImageFpsPICO;

typedef struct XrCameraDeviceCreateInfoPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrCameraIdPICO              cameraId;
} XrCameraDeviceCreateInfoPICO;

typedef struct XrCreateCameraDeviceCompletionPICO {
    XrStructureType       type;
    void* XR_MAY_ALIAS    next;
    XrResult              futureResult;
    XrCameraDevicePICO    device;
} XrCreateCameraDeviceCompletionPICO;

typedef struct XrCameraCaptureSessionCreateInfoPICO {
    XrStructureType                                   type;
    const void* XR_MAY_ALIAS                          next;
    XrCameraDevicePICO                                camera;
    uint32_t                                          configCount;
    const XrCameraCapabilityBaseHeaderPICO* const*    configs;
} XrCameraCaptureSessionCreateInfoPICO;

typedef struct XrCreateCameraCaptureSessionCompletionPICO {
    XrStructureType               type;
    void* XR_MAY_ALIAS            next;
    XrResult                      futureResult;
    XrCameraCaptureSessionPICO    captureSession;
} XrCreateCameraCaptureSessionCompletionPICO;

typedef struct XrCameraIntrinsicsPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrVector2f                  focalLength;
    XrVector2f                  principalPoint;
    XrVector2f                  fov;
} XrCameraIntrinsicsPICO;

typedef struct XrCameraExtrinsicsPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrPosef                     pose;
} XrCameraExtrinsicsPICO;

typedef struct XrCameraCaptureBeginInfoPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
} XrCameraCaptureBeginInfoPICO;

typedef struct XrCameraImageAcquireInfoPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrTime                      lastCaptureTime;
} XrCameraImageAcquireInfoPICO;

typedef struct XrCameraImagePICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    XrTime                      captureTime;
    XrCameraImageIdPICO         imageId;
} XrCameraImagePICO;

typedef struct XR_MAY_ALIAS XrCameraImageDataBaseHeaderPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
} XrCameraImageDataBaseHeaderPICO;

typedef struct XrCameraImageDataRawBufferPICO {
    XrStructureType             type;
    const void* XR_MAY_ALIAS    next;
    uint32_t                    width;
    uint32_t                    height;
    uint32_t                    stride;
    uint32_t                    bytesPerPixel;
    uint32_t                    pixelStride;
    uint32_t                    bufferSize;
    uint8_t*                    buffer;
} XrCameraImageDataRawBufferPICO;

typedef XrResult (XRAPI_PTR *PFN_xrEnumerateAvailableCamerasPICO)(XrInstance instance, const XrAvailableCamerasEnumerateInfoPICO* enumerateInfo, uint32_t cameraIdCapacityInput, uint32_t* cameraIdCountOutput, XrCameraIdPICO* cameraIds);
typedef XrResult (XRAPI_PTR *PFN_xrEnumerateCameraPropertyTypesPICO)(XrInstance instance, XrCameraIdPICO cameraId, uint32_t typeCapacityInput, uint32_t* typeCountOutput, XrCameraPropertyTypePICO* types);
typedef XrResult (XRAPI_PTR *PFN_xrGetCameraPropertiesPICO)(XrInstance instance, const XrCameraPropertiesGetInfoPICO* getInfo, XrCameraPropertiesPICO* properties);
typedef XrResult (XRAPI_PTR *PFN_xrEnumerateCameraCapabilityTypesPICO)(XrInstance instance, XrCameraIdPICO cameraId, uint32_t typeCapacityInput, uint32_t* typeCountOutput, XrCameraCapabilityTypePICO* types);
typedef XrResult (XRAPI_PTR *PFN_xrGetCameraSupportedCapabilitiesPICO)(XrInstance instance, const XrCameraSupportedCapabilitiesGetInfoPICO* getInfo, XrCameraSupportedCapabilitiesPICO* capabilities);
typedef XrResult (XRAPI_PTR *PFN_xrCreateCameraDeviceAsyncPICO)(XrInstance instance, const XrCameraDeviceCreateInfoPICO* createInfo, XrFutureEXT* future);
typedef XrResult (XRAPI_PTR *PFN_xrCreateCameraDeviceCompletePICO)(XrInstance instance, XrFutureEXT future, XrCreateCameraDeviceCompletionPICO* completion);
typedef XrResult (XRAPI_PTR *PFN_xrDestroyCameraDevicePICO)(XrCameraDevicePICO device);
typedef XrResult (XRAPI_PTR *PFN_xrCreateCameraCaptureSessionAsyncPICO)(XrSession session, const XrCameraCaptureSessionCreateInfoPICO* createInfo, XrFutureEXT* future);
typedef XrResult (XRAPI_PTR *PFN_xrCreateCameraCaptureSessionCompletePICO)(XrSession session, XrFutureEXT future, XrCreateCameraCaptureSessionCompletionPICO* completion);
typedef XrResult (XRAPI_PTR *PFN_xrDestroyCameraCaptureSessionPICO)(XrCameraCaptureSessionPICO captureSession);
typedef XrResult (XRAPI_PTR *PFN_xrGetCameraIntrinsicsPICO)(XrCameraCaptureSessionPICO session, XrCameraIntrinsicsPICO* intrinsics);
typedef XrResult (XRAPI_PTR *PFN_xrGetCameraExtrinsicsPICO)(XrCameraCaptureSessionPICO session, XrCameraExtrinsicsPICO* extrinsics);
typedef XrResult (XRAPI_PTR *PFN_xrBeginCameraCapturePICO)(XrCameraCaptureSessionPICO session, XrCameraCaptureBeginInfoPICO* beginInfo);
typedef XrResult (XRAPI_PTR *PFN_xrEndCameraCapturePICO)(XrCameraCaptureSessionPICO session);
typedef XrResult (XRAPI_PTR *PFN_xrAcquireCameraImagePICO)(XrCameraCaptureSessionPICO session, const XrCameraImageAcquireInfoPICO* acquireInfo, XrCameraImagePICO* image);
typedef XrResult (XRAPI_PTR *PFN_xrGetCameraImageDataPICO)(XrCameraCaptureSessionPICO session, XrCameraImageIdPICO imageId, XrCameraImageDataBaseHeaderPICO* imageData);
typedef XrResult (XRAPI_PTR *PFN_xrReleaseCameraImagePICO)(XrCameraCaptureSessionPICO session, XrCameraImageIdPICO imageId);

#ifndef XR_NO_PROTOTYPES
#ifdef XR_EXTENSION_PROTOTYPES
XRAPI_ATTR XrResult XRAPI_CALL xrEnumerateAvailableCamerasPICO(
    XrInstance                                  instance,
    const XrAvailableCamerasEnumerateInfoPICO*  enumerateInfo,
    uint32_t                                    cameraIdCapacityInput,
    uint32_t*                                   cameraIdCountOutput,
    XrCameraIdPICO*                             cameraIds);

XRAPI_ATTR XrResult XRAPI_CALL xrEnumerateCameraPropertyTypesPICO(
    XrInstance                                  instance,
    XrCameraIdPICO                              cameraId,
    uint32_t                                    typeCapacityInput,
    uint32_t*                                   typeCountOutput,
    XrCameraPropertyTypePICO*                   types);

XRAPI_ATTR XrResult XRAPI_CALL xrGetCameraPropertiesPICO(
    XrInstance                                  instance,
    const XrCameraPropertiesGetInfoPICO*        getInfo,
    XrCameraPropertiesPICO*                     properties);

XRAPI_ATTR XrResult XRAPI_CALL xrEnumerateCameraCapabilityTypesPICO(
    XrInstance                                  instance,
    XrCameraIdPICO                              cameraId,
    uint32_t                                    typeCapacityInput,
    uint32_t*                                   typeCountOutput,
    XrCameraCapabilityTypePICO*                 types);

XRAPI_ATTR XrResult XRAPI_CALL xrGetCameraSupportedCapabilitiesPICO(
    XrInstance                                  instance,
    const XrCameraSupportedCapabilitiesGetInfoPICO* getInfo,
    XrCameraSupportedCapabilitiesPICO*          capabilities);

XRAPI_ATTR XrResult XRAPI_CALL xrCreateCameraDeviceAsyncPICO(
    XrInstance                                  instance,
    const XrCameraDeviceCreateInfoPICO*         createInfo,
    XrFutureEXT*                                future);

XRAPI_ATTR XrResult XRAPI_CALL xrCreateCameraDeviceCompletePICO(
    XrInstance                                  instance,
    XrFutureEXT                                 future,
    XrCreateCameraDeviceCompletionPICO*         completion);

XRAPI_ATTR XrResult XRAPI_CALL xrDestroyCameraDevicePICO(
    XrCameraDevicePICO                          device);

XRAPI_ATTR XrResult XRAPI_CALL xrCreateCameraCaptureSessionAsyncPICO(
    XrSession                                   session,
    const XrCameraCaptureSessionCreateInfoPICO* createInfo,
    XrFutureEXT*                                future);

XRAPI_ATTR XrResult XRAPI_CALL xrCreateCameraCaptureSessionCompletePICO(
    XrSession                                   session,
    XrFutureEXT                                 future,
    XrCreateCameraCaptureSessionCompletionPICO* completion);

XRAPI_ATTR XrResult XRAPI_CALL xrDestroyCameraCaptureSessionPICO(
    XrCameraCaptureSessionPICO                  captureSession);

XRAPI_ATTR XrResult XRAPI_CALL xrGetCameraIntrinsicsPICO(
    XrCameraCaptureSessionPICO                  session,
    XrCameraIntrinsicsPICO*                     intrinsics);

XRAPI_ATTR XrResult XRAPI_CALL xrGetCameraExtrinsicsPICO(
    XrCameraCaptureSessionPICO                  session,
    XrCameraExtrinsicsPICO*                     extrinsics);

XRAPI_ATTR XrResult XRAPI_CALL xrBeginCameraCapturePICO(
    XrCameraCaptureSessionPICO                  session,
    XrCameraCaptureBeginInfoPICO*               beginInfo);

XRAPI_ATTR XrResult XRAPI_CALL xrEndCameraCapturePICO(
    XrCameraCaptureSessionPICO                  session);

XRAPI_ATTR XrResult XRAPI_CALL xrAcquireCameraImagePICO(
    XrCameraCaptureSessionPICO                  session,
    const XrCameraImageAcquireInfoPICO*         acquireInfo,
    XrCameraImagePICO*                          image);

XRAPI_ATTR XrResult XRAPI_CALL xrGetCameraImageDataPICO(
    XrCameraCaptureSessionPICO                  session,
    XrCameraImageIdPICO                         imageId,
    XrCameraImageDataBaseHeaderPICO*            imageData);

XRAPI_ATTR XrResult XRAPI_CALL xrReleaseCameraImagePICO(
    XrCameraCaptureSessionPICO                  session,
    XrCameraImageIdPICO                         imageId);
#endif /* XR_EXTENSION_PROTOTYPES */
#endif /* !XR_NO_PROTOTYPES */



#endif // XR_PICO_camera_image
