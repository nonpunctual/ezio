## Planes

IORegistry planes, defined as constants in `IOKitKeys.h`:

```
IORegistry
├── IOService       ← main driver/service stack (default)
├── IOPower         ← power management relationships
├── IODeviceTree    ← firmware/ACPI device tree view
├── IOAudio         ← audio device graph
├── IOFireWire      ← FireWire topology (legacy, likely empty on modern Macs)
└── IOUSB           ← USB controller/device topology
```

- 6 planes total. On modern Apple Silicon Macs
- IOFireWire` and `IOAudio` will likely be empty
- `IOService` is the default plane used by `ioreg -a -l`

## Node Attribute Types

Each node in the IORegistry has the following attribute types & every node line in raw ioreg output looks like:

```
+-o AppleARMPE  <class AppleARMPE, id 0x1000002bc, registered, matched, active, busy 0 (42292 ms), retain 49>
     ^^^^^^^^         ^^^^^^^^^^^      ^^^^^^^^^^^  ^^^^^^^^^^  ^^^^^^^  ^^^^^^  ^^^^^^^^^^^^^^^^^^^  ^^^^^^^
     Name             Class            ID           State flags                  Busy state            Retain count
```

Full taxonomy:

| Type | ioreg flag | Description |
|---|---|---|
| **Plane** | `-p` | Which relationship graph (IOService, IOUSB, etc.) |
| **Name** | `-n` | `IORegistryEntryName`, may include location (`pci@f0000000`) |
| **Location** | (part of `-n`) | The `@address` suffix — bus address of the entry |
| **Class** | `-c` | C++ kernel class (e.g. `IOHIDDevice`, `AppleSMC`) |
| **Inheritance** | `-i` | Full superclass chain of the class |
| **ID** | — | Unique numeric registry entry ID |
| **State** | — | `registered`, `matched`, `active` (boolean flags) |
| **Busy** | — | Busy count + time spent busy |
| **Retain count** | — | Kernel reference count |
| **Properties** | `-k`, `-l` | Key-value dictionary — the actual device data |

**Properties** are the deepest layer: 

- each node can have many of them
- keys/values vary entirely by device class
- This is the layer `ezio` currently searches.

The full list of unique property keys found in the IOService plane on this computer (3,746 total) is in `ioservice-keys.txt`. 

- This is specific to this computer
- `ioreg` output is not heterogeneous from Mac model to model
  - i.e., different hardware will produce different keys

## Subsystem Taxonomy

23 identifiable subsystems, grouped by key naming conventions. ~1,500+ keys are highly-specific, one-off properties or internal Apple references with no clear user-facing grouping.

| Subsystem | Key patterns | Notes |
|---|---|---|
| **GPU / Graphics** | `agx-*`, `AGX*`, `gfx-*`, `gpu-*`, `IOMFB*`, `IOGLBundleName` | Apple Silicon GPU |
| **Neural Engine** | `ane-*`, `#ane-num-clusters` | ANE accelerator |
| **Display** | `dp-*`, `display-*`, `backlight-*`, `APT*`, `AOD*` | Panel + DCP |
| **Ambient Light** | `ALS*`, `AmbientBrightness`, `ambient-light-sensor-*` | |
| **Battery** | `AbsoluteCapacity`, `Amperage`, `AppleRawBattery*`, `AppleRawCurrentCapacity`, `AppleRawMaxCapacity`, `AppleVoltageDictionary` | |
| **Power / Thermal** | `#pkg-*`, `lts-*`, `die0-*`, `dcs-*`, `voltage-*`, `soc-*`, `IOPowerManagement` | |
| **CPU / Perf** | `cpu-*`, `perf-*`, `l2-*`, `clock-*`, `AppleARMPerformance*` | |
| **Always-On Processor** | `aop-*`, `AOT*`, `AOD*` | |
| **HID** | `HID*` | Keyboards, mice, trackpads |
| **Accelerometer / Sensors** | `accel-*`, `acc-*` | Motion sensors |
| **Audio** | `IOAudio*`, `amp-*` | |
| **USB / Charging** | `usb-*`, `IOAccessory*`, `ACIPCInterface*`, `ActiveCable`, `ADP is generic pipe`, `Adapter*` | |
| **Bluetooth / WiFi** | `IOUserBluetooth*`, `AppleBCMWLAN*` | |
| **Network** | `IOInterface*`, `IONetwork*`, `IOMACAddress` | |
| **PCIe** | `IOPCI*`, `apcie-*`, `gl9755-*` | |
| **Storage** | `IOStorage*`, `AppleNANDStatus`, `APFS*` | |
| **Media / JPEG** | `AppleJPEG*`, `IOProResHW*` | HW decode/encode |
| **Security / Crypto** | `AKS*`, `aes-*` | AppleKeyStore, AES engine |
| **DMA / IOMMU** | `dart-*`, `iommu-*`, `piodma-*`, `ioa[0-9]-` | |
| **Platform / System** | `IOPlatform*`, `IOModel`, `IOVendor`, `AAPL,*` | Machine identity |
| **Firmware / DeviceTree** | `#address-cells`, `function-*`, `info-*`, `device-*` | Low-level firmware nodes |
| **Panic / Debug** | `panic-*`, `AppleDiagnosticData`, `IOKitDiagnostics` | |
| **IOKit Meta** | `IOObject*`, `IORegistry*`, `IOProvider*`, `IOClass`, `IOServiceState` | Framework internals |

## Structure

Name and Class are not separate levels. They're both attributes of the same node. The hierarchy is:

```
IORegistry
└── Plane
    └── Node  ← has a name, a class, an ID, and properties — all at once
        ├── Properties (key-value pairs)
        └── Child nodes (same structure, recursively)
```

Class is a filter across the tree, not a level within it. When you say "go into AppleARMCPU"
you're not descending a level — you're filtering to show only nodes whose class matches.

The result is a flat list of instances, each of which is already a full node with name, ID,
and properties. Multiple instances of the same class can share the same name and are only
distinguishable by their ID (e.g. 0x100000300, 0x1000002ff). So, the navigable levels in `ioreg` are really just two things:

1. The tree structure: parent/child relationships between nodes
2. The properties bag: key-value pairs hanging off each node

Class, name, and ID are all just ways to identify or filter nodes, not levels you descend through.

```
IORegistry
└── Plane
    └── Node
        ├── attributes (name, class, ID, state flags)
        ├── properties (key-value bag)
        └── Node
            ├── attributes
            ├── properties
            └── Node
                └── ...
```

The tree is nodes all the way down. The only thing that changes at the bottom of the tree is that leaf nodes have no children, just attributes and properties.

The full node tree for all 6 planes (3,524 lines) is in `node-tree.txt`. Node counts per plane:

- IOService: 2,320 nodes
- IOPower: 736 nodes
- IODeviceTree: 454 nodes
- IOUSB: 5 nodes
- IOAudio: 1 node (empty)
- IOFireWire: 1 node (empty)

- Every plane is the same:
  - `Root <IORegistryEntry>` → `J516sAP <IOPlatformExpertDevice>`
  - confirming the same physical hardware viewed through different lenses
- IOService has 2,320 nodes
  - nearly 5x more than IOPower (736) which makes sense since IOPower only tracks nodes that participate in power management
- IODeviceTree's 454 nodes are the firmware-visible subset
  - much flatter view of the same hardware

## Classes Per Plane

All classes observed on this machine per plane. `IOAudio` and `IOFireWire` contain only `IORegistryEntry` on Apple Silicon.

```
IORegistry
├── IOService (412 classes)  ← main driver/service stack (default)
│   ├── AFKEPInterfaceKextV2
│   ├── AFKEPInterfaceServiceKextV2
│   ├── AFKEndpointInterfaceUserClient
│   ├── AFKFirmwareService
│   ├── AFKLocalMemoryDescriptorManager
│   ├── AGXAcceleratorG15X
│   ├── AGXArmFirmwareMapper
│   ├── AGXDeviceUserClient
│   ├── AGXFirmwareKextG15RTBuddy
│   ├── AIDImageDownloader
│   ├── ANEClientHints
│   ├── APCIECMSIController
│   ├── AUC
│   ├── AppleA7IOPNub
│   ├── AppleANS3CGv2Controller
│   ├── AppleAOPAudioClientManager
│   ├── AppleAOPAudioController
│   ├── AppleAOPAudioDeviceNode
│   ├── AppleAOPAudioLPMicInDevice
│   ├── AppleAOPAudioPDM2Device
│   ├── AppleAOPAudioService
│   ├── AppleAOPAudioUserClient
│   ├── AppleAOPVoiceTriggerController
│   ├── AppleAOPVoiceTriggerUserClient
│   ├── AppleAPFSContainer
│   ├── AppleAPFSContainerScheme
│   ├── AppleAPFSGraft
│   ├── AppleAPFSMedia
│   ├── AppleAPFSMediaBSDClient
│   ├── AppleAPFSSnapshot
│   ├── AppleAPFSVolume
│   ├── AppleAPFSVolumeBSDClient
│   ├── AppleARMBacklight
│   ├── AppleARMBootPerf
│   ├── AppleARMCPU
│   ├── AppleARMIICDevice
│   ├── AppleARMIISDevice
│   ├── AppleARMIODevice
│   ├── AppleARMLightEmUp
│   ├── AppleARMNORFlashDevice
│   ├── AppleARMNORNVRAM
│   ├── AppleARMPE
│   ├── AppleARMPMUPowerSensor
│   ├── AppleARMPMUTempSensor
│   ├── AppleARMPWMDevice
│   ├── AppleARMSFRManifest
│   ├── AppleARMSPIDevice
│   ├── AppleARMSPIFlashController
│   ├── AppleARMSPMIDevice
│   ├── AppleARMSlowAdaptiveClockingManager
│   ├── AppleARMWatchdogTimer
│   ├── AppleASCWrapV6
│   ├── AppleASCWrapV6SEP
│   ├── AppleATCDPAltModePort
│   ├── AppleATCDPHDMIPort
│   ├── AppleATCDPINAdapterPort
│   ├── AppleAVD
│   ├── AppleAVE2Driver
│   ├── AppleActuatorDevice
│   ├── AppleActuatorDeviceUserClient
│   ├── AppleActuatorHIDEventDriver
│   ├── AppleBSDKextStarter
│   ├── AppleBTM
│   ├── AppleBiometricServices
│   ├── AppleBluetoothModule
│   ├── AppleCLPC
│   ├── AppleCLPCUserClient
│   ├── AppleCS42L84Audio
│   ├── AppleCS42L84Mikey
│   ├── AppleConvergedIPCOLYBTControl
│   ├── AppleConvergedIPCOLYBTCoreDumpProvider
│   ├── AppleConvergedIPCOLYBTLogProvider
│   ├── AppleConvergedIPCRTIDevice
│   ├── AppleConvergedIPCRTIInterface
│   ├── AppleConvergedIPCSkywalkInterface
│   ├── AppleConvergedPCI
│   ├── AppleCredentialManager
│   ├── AppleCredentialManagerUserClient
│   ├── AppleDCPDPTXRemoteHDCPInterfaceProxy
│   ├── AppleDCPDPTXRemotePortProxy
│   ├── AppleDCPDPTXRemotePortUFP
│   ├── AppleDCPExpert
│   ├── AppleDCPLinkServiceSoC
│   ├── AppleDeviceManagementHIDEventService
│   ├── AppleDiagnosticDataAccessReadOnly
│   ├── AppleDialogSPMIPMU
│   ├── AppleDialogSPMIPMURTC
│   ├── AppleDiskImagesController
│   ├── AppleDisplayConnectionManager
│   ├── AppleDockChannel
│   ├── AppleDockChannelDevice
│   ├── AppleEmbeddedAudioDevice
│   ├── AppleEmbeddedNVMeTemperatureSensor
│   ├── AppleEmbeddedSimpleSPINORFlasherDriver
│   ├── AppleEventLogHandler
│   ├── AppleExternalSecondaryAudio
│   ├── AppleFDEKeyStore
│   ├── AppleFairplayTextCrypter
│   ├── AppleGCResource
│   ├── AppleGCResourceDeviceUserClient
│   ├── AppleH13CamIn
│   ├── AppleH13CamInUserClient
│   ├── AppleH15IO
│   ├── AppleH15MemCacheController
│   ├── AppleH15PlatformErrorHandler
│   ├── AppleHDCPInterface
│   ├── AppleHDMIPortController
│   ├── AppleHIDKeyboardEventDriverV2
│   ├── AppleHIDTransportBootloaderCBOR
│   ├── AppleHIDTransportBootloaderHIDDevice
│   ├── AppleHIDTransportBootloaderRTBuddy
│   ├── AppleHIDTransportDeviceFIFO
│   ├── AppleHIDTransportHIDDevice
│   ├── AppleHIDTransportHibernator
│   ├── AppleHIDTransportInterface
│   ├── AppleHIDTransportManagement
│   ├── AppleHIDTransportProtocolSCMFIFO
│   ├── AppleHPMARMSPMI
│   ├── AppleHPMDeviceHALType3
│   ├── AppleHPMInterfaceType10
│   ├── AppleHPMInterfaceType11
│   ├── AppleHPMLDCMType2
│   ├── AppleIPAppender
│   ├── AppleImage4
│   ├── AppleImage4UserClient
│   ├── AppleInterruptControllerV3
│   ├── AppleJPEGDriver
│   ├── AppleKeyStore
│   ├── AppleKeyStoreTest
│   ├── AppleKeyStoreUserClient
│   ├── AppleLEAPController_T6030
│   ├── AppleLockdownMode
│   ├── AppleM2ScalerCSCDriver
│   ├── AppleM68Buttons
│   ├── AppleMCA2Cluster_T6030
│   ├── AppleMCA2Controller_T6030
│   ├── AppleMCA2Switch
│   ├── AppleMesaResources
│   ├── AppleMesaSEPDriver
│   ├── AppleMesaShim
│   ├── AppleMobileApNonce
│   ├── AppleMobileFileIntegrity
│   ├── AppleMultiFunctionManager
│   ├── AppleMultitouchDevice
│   ├── AppleMultitouchDeviceUserClient
│   ├── AppleMultitouchTrackpadHIDEventDriver
│   ├── AppleMxWrapACIO
│   ├── AppleNVMeEAN
│   ├── AppleNVMeEANUC
│   ├── AppleNVMeNamespaceDevice
│   ├── AppleOLYHAL
│   ├── AppleOnboardSerialBSDClient
│   ├── ApplePCIECHostBridge
│   ├── ApplePCIECLegacyIntController
│   ├── ApplePCIEHostBridge
│   ├── ApplePCIEMSIController
│   ├── ApplePCIeCPIODMA
│   ├── ApplePMGRNub
│   ├── ApplePMPFirmware
│   ├── ApplePMPv2
│   ├── AppleParadeDP855TCON
│   ├── ApplePassthroughPPM
│   ├── AppleProResHW
│   ├── AppleRSMChannelController
│   ├── AppleS5L8920XFPWM
│   ├── AppleS5L8940XI2CController
│   ├── AppleS5L8960XNCO
│   ├── AppleS8000AESAccelerator
│   ├── AppleS8000DWI
│   ├── AppleSCSISubsystemGlobals
│   ├── AppleSDXC
│   ├── AppleSDXCBlockStorageDevice
│   ├── AppleSDXCSDDetect
│   ├── AppleSDXCSlot
│   ├── AppleSEPDeviceService
│   ├── AppleSEPHDCPManager
│   ├── AppleSEPManager
│   ├── AppleSEPUserClient
│   ├── AppleSEPXARTService
│   ├── AppleSMCChargerUtil
│   ├── AppleSMCClient
│   ├── AppleSMCInterface
│   ├── AppleSMCKeysEndpoint
│   ├── AppleSMCPMU
│   ├── AppleSMCSensorDispatcher
│   ├── AppleSMCSensorDispatcherUserClient
│   ├── AppleSN012776Amp
│   ├── AppleSPIMCController
│   ├── AppleSPMIController
│   ├── AppleSPU
│   ├── AppleSPUAppDriver
│   ├── AppleSPUAppInterface
│   ├── AppleSPUFirmwareService
│   ├── AppleSPUHIDDevice
│   ├── AppleSPUHIDDeviceUserClient
│   ├── AppleSPUHIDDriver
│   ├── AppleSPUHIDDriverUserClient
│   ├── AppleSPUHIDInterface
│   ├── AppleSPUProfileDriver
│   ├── AppleSPUTimesyncV2
│   ├── AppleSPUVD6286
│   ├── AppleSSE
│   ├── AppleSSEUserClient
│   ├── AppleSamsungSerial
│   ├── AppleSandDollar
│   ├── AppleSecondaryAudio
│   ├── AppleSerialShim
│   ├── AppleSimpleUARTSync
│   ├── AppleSmartBattery
│   ├── AppleSmartBatteryManager
│   ├── AppleSmartIO
│   ├── AppleSmartIODMAController
│   ├── AppleSmartIODMANub
│   ├── AppleStockholmControl
│   ├── AppleStockholmControlConfig
│   ├── AppleStockholmSPMI
│   ├── AppleSystemPolicy
│   ├── AppleSystemPolicyUserClient
│   ├── AppleT6020PCIePIODMA
│   ├── AppleT602XATCDPXBAR
│   ├── AppleT6030ANEHAL
│   ├── AppleT6030PCIe
│   ├── AppleT6030PMGR
│   ├── AppleT6030SOCTuner
│   ├── AppleT603XDisplayCrossbar
│   ├── AppleT8101GPIOIC
│   ├── AppleT8110DART
│   ├── AppleT8122PCIeC
│   ├── AppleT8122TypeCPhy
│   ├── AppleT8122USBXDCI
│   ├── AppleT8122USBXHCI
│   ├── AppleTCONComponent
│   ├── AppleThunderboltDPConnectionManager
│   ├── AppleThunderboltDPInAdapterOS
│   ├── AppleThunderboltHALType5
│   ├── AppleThunderboltIPPort
│   ├── AppleThunderboltIPService
│   ├── AppleThunderboltNHIType5
│   ├── AppleThunderboltPCIDownAdapterType5
│   ├── AppleThunderboltUSBDownAdapter
│   ├── AppleTrustedAccessoryManager
│   ├── AppleTrustedAccessoryManagerUserClient
│   ├── AppleTypeCRetimer
│   ├── AppleUIOMem
│   ├── AppleUSB20XHCIARMPort
│   ├── AppleUSB30XHCIARMPort
│   ├── AppleUSBDeviceNCMControl
│   ├── AppleUSBDeviceNCMData
│   ├── AppleUSBDeviceNCMPrivateEthernetInterface
│   ├── AppleUSBHostCompositeDevice
│   ├── AppleUSBHostDeviceUserClient
│   ├── AppleUSBHostFrameworkInterfaceClient
│   ├── AppleUSBHostResourcesTypeC
│   ├── AppleUSBUserHCIResources
│   ├── AppleUserHIDDevice
│   ├── AppleUserHIDEventService
│   ├── AudioDMAChannel
│   ├── AudioDMAController
│   ├── BTDebug
│   ├── BootPolicy
│   ├── BootPolicyUserClient
│   ├── CCDataPipe
│   ├── CCDataStream
│   ├── CCIOService
│   ├── CCLogPipe
│   ├── CCLogStream
│   ├── CoreAnalyticsHub
│   ├── CoreAnalyticsMessenger
│   ├── CoreAnalyticsUserClient
│   ├── CoreKDLDriver
│   ├── CoreKDLUserClient
│   ├── DCPAVAudioDMADelegate
│   ├── DCPAVControllerProxy
│   ├── DCPAVDeviceProxy
│   ├── DCPAVPowerControllerProxy
│   ├── DCPAVRemoteSACControllerProxy
│   ├── DCPAVSACController
│   ├── DCPAVServiceProxy
│   ├── DCPAVVideoInterfaceProxy
│   ├── DCPDPControllerProxy
│   ├── DCPDPDeviceProxy
│   ├── DCPDPServiceProxy
│   ├── DCPEndpointV2
│   ├── EndpointSecurityDriver
│   ├── EndpointSecurityExternalClient
│   ├── H11ANEIn
│   ├── H1xANELoadBalancer
│   ├── HibernationService
│   ├── IOAVBNub
│   ├── IOAVBValidate
│   ├── IOApplePartitionScheme
│   ├── IOAudio2DeviceUserClient
│   ├── IOBlockStorageDriver
│   ├── IOBluetoothACPIMethods
│   ├── IOBluetoothDevice
│   ├── IOBluetoothHCIController
│   ├── IOBluetoothHCIUserClient
│   ├── IOCoastGuardSARTMapper
│   ├── IODARTMapper
│   ├── IODARTMapperNub
│   ├── IODPPortService
│   ├── IODTNVRAM
│   ├── IODTNVRAMDiags
│   ├── IODTNVRAMPlatformNotifier
│   ├── IODTNVRAMVariables
│   ├── IODiskImageBlockStorageDeviceOutKernel
│   ├── IODisplayWrangler
│   ├── IOEmbeddedNVMeBlockDevice
│   ├── IOEthernetInterface
│   ├── IOGUIDPartitionScheme
│   ├── IOHDIXController
│   ├── IOHDIXHDDriveOutKernel
│   ├── IOHDIXHDDriveOutKernelUserClient
│   ├── IOHIDEventServiceUserClient
│   ├── IOHIDEventSystemUserClient
│   ├── IOHIDInterface
│   ├── IOHIDLibUserClient
│   ├── IOHIDParamUserClient
│   ├── IOHIDPowerSource
│   ├── IOHIDPowerSourceController
│   ├── IOHIDResource
│   ├── IOHIDResourceDeviceUserClient
│   ├── IOHIDSystem
│   ├── IOHIDUserClient
│   ├── IOHIDUserDevice
│   ├── IOKitRegistryCompatibility
│   ├── IOMedia
│   ├── IOMediaBSDClient
│   ├── IOMobileFramebufferShim
│   ├── IOMobileFramebufferUserClient
│   ├── IONetworkStack
│   ├── IONetworkStackUserClient
│   ├── IOPCIDevice
│   ├── IOPMrootDomain
│   ├── IOPlatformDevice
│   ├── IOPlatformExpertDevice
│   ├── IOPortFeatureLDCMUserClient
│   ├── IOPortFeaturePowerIn
│   ├── IOPortFeaturePowerSource
│   ├── IOPortTransportStateCC
│   ├── IOPortTransportStateDisplayPort
│   ├── IOPortTransportStateSD
│   ├── IOPortTransportStateUSB2
│   ├── IOPortTransportStateUSB3
│   ├── IORegistryEntry
│   ├── IOReportHub
│   ├── IOReportUserClient
│   ├── IOResources
│   ├── IORootParent
│   ├── IOSerialBSDClient
│   ├── IOServiceCompatibility
│   ├── IOSkywalkKernelPipeBSDClient
│   ├── IOSkywalkLegacyEthernet
│   ├── IOSkywalkLegacyEthernetInterface
│   ├── IOSkywalkNetworkBSDClient
│   ├── IOSurfaceAcceleratorClient
│   ├── IOSurfaceRoot
│   ├── IOSurfaceRootUserClient
│   ├── IOSystemStateNotification
│   ├── IOTBTTunnelClientInterfaceManager
│   ├── IOThunderboltControllerType5
│   ├── IOThunderboltLocalNode
│   ├── IOThunderboltPort
│   ├── IOThunderboltSwitchType5
│   ├── IOThunderboltXDomainServiceClientManager
│   ├── IOTimeSyncClockManager
│   ├── IOTimeSyncClockManagerDaemonClient
│   ├── IOTimeSyncDaemonService
│   ├── IOTimeSyncDaemonUserClient
│   ├── IOTimeSyncDomain
│   ├── IOTimeSyncDomainDaemonClient
│   ├── IOTimeSyncRootService
│   ├── IOTimeSyncServiceDaemonClient
│   ├── IOTimeSyncSyncDaemonClient
│   ├── IOTimeSyncTimeSyncTimePort
│   ├── IOTimeSyncTranslationMach
│   ├── IOTimeSyncgPTPManager
│   ├── IOTimeSyncgPTPManagerDaemonClient
│   ├── IOUSBDeviceConfigurator
│   ├── IOUSBDeviceInterface
│   ├── IOUSBHostDevice
│   ├── IOUSBHostInterface
│   ├── IOUSBMassStorageResource
│   ├── IOUserEthernetController
│   ├── IOUserEthernetInterface
│   ├── IOUserEthernetResource
│   ├── IOUserEthernetResourceUserClient
│   ├── IOUserNetworkWLAN
│   ├── IOUserResources
│   ├── IOUserSerial
│   ├── IOUserServer
│   ├── IOUserService
│   ├── IOUserUserClient
│   ├── IOWatchdogUserClient
│   ├── NVMeSEPNotifier
│   ├── PassthruInterruptController
│   ├── RTBuddy
│   ├── RTBuddyEndpointService
│   ├── RTBuddyIOReportingEndpoint
│   ├── RTBuddyService
│   ├── RTBuddyTraceKitEndpoint
│   ├── RootDomainUserClient
│   ├── com_apple_AppleFSCompression_AppleFSCompressionTypeDataless
│   ├── com_apple_AppleFSCompression_AppleFSCompressionTypeZlib
│   ├── com_apple_BootCache
│   ├── com_apple_driver_FairPlayIOKit
│   ├── com_apple_driver_FairPlayIOKitUserClient
│   ├── com_apple_filesystems_apfs
│   ├── com_apple_filesystems_hfs
│   ├── com_apple_filesystems_hfs_encodings
│   ├── com_apple_filesystems_lifs
│   └── com_apple_filesystems_nfs
├── IOPower (100 classes)  ← power management relationships
│   ├── AFKEPInterfaceKextV2
│   ├── AFKEPInterfaceServiceKextV2
│   ├── AFKEndpointInterfaceUserClient
│   ├── AGXAcceleratorG15X
│   ├── AppleANS3CGv2Controller
│   ├── AppleAOPAudioClientManager
│   ├── AppleAOPAudioController
│   ├── AppleAOPAudioLPMicInDevice
│   ├── AppleAOPAudioPDM2Device
│   ├── AppleAOPVoiceTriggerController
│   ├── AppleARMBootPerf
│   ├── AppleAVD
│   ├── AppleAVE2Driver
│   ├── AppleActuatorDevice
│   ├── AppleBluetoothModule
│   ├── AppleCS42L84Audio
│   ├── AppleConvergedIPCOLYBTControl
│   ├── AppleConvergedPCI
│   ├── AppleCredentialManager
│   ├── AppleDCPDPTXRemotePortProxy
│   ├── AppleDCPExpert
│   ├── AppleDialogSPMIPMU
│   ├── AppleEmbeddedAudioDevice
│   ├── AppleExternalSecondaryAudio
│   ├── AppleFDEKeyStore
│   ├── AppleH13CamIn
│   ├── AppleHDCPInterface
│   ├── AppleHIDTransportDeviceFIFO
│   ├── AppleHIDTransportHibernator
│   ├── AppleHPMARMSPMI
│   ├── AppleHPMInterfaceType10
│   ├── AppleHPMInterfaceType11
│   ├── AppleIPAppender
│   ├── AppleJPEGDriver
│   ├── AppleKeyStore
│   ├── AppleLEAPController_T6030
│   ├── AppleM2ScalerCSCDriver
│   ├── AppleM68Buttons
│   ├── AppleMCA2Controller_T6030
│   ├── AppleMCA2Switch
│   ├── AppleMesaSEPDriver
│   ├── AppleMultiFunctionManager
│   ├── AppleOLYHAL
│   ├── ApplePCIECHostBridge
│   ├── ApplePCIEHostBridge
│   ├── AppleProResHW
│   ├── AppleRSMChannelController
│   ├── AppleSDXC
│   ├── AppleSDXCBlockStorageDevice
│   ├── AppleSDXCSlot
│   ├── AppleSEPManager
│   ├── AppleSMCKeysEndpoint
│   ├── AppleSN012776Amp
│   ├── AppleSPU
│   ├── AppleSPUAppDriver
│   ├── AppleSPUAppInterface
│   ├── AppleSPUHIDDriver
│   ├── AppleSPUHIDInterface
│   ├── AppleSPUTimesyncV2
│   ├── AppleSPUVD6286
│   ├── AppleSSE
│   ├── AppleSamsungSerial
│   ├── AppleSandDollar
│   ├── AppleSecondaryAudio
│   ├── AppleSmartBatteryManager
│   ├── AppleStockholmControl
│   ├── AppleStockholmSPMI
│   ├── AppleSystemPolicy
│   ├── AppleT6030PCIe
│   ├── AppleT8122PCIeC
│   ├── AppleT8122USBXDCI
│   ├── AppleT8122USBXHCI
│   ├── AppleThunderboltHALType5
│   ├── AppleTrustedAccessoryManager
│   ├── AppleUSB20XHCIARMPort
│   ├── AppleUSB30XHCIARMPort
│   ├── AppleUserHIDDevice
│   ├── AppleUserHIDEventService
│   ├── AudioDMAChannel
│   ├── AudioDMAController
│   ├── BootPolicy
│   ├── CoreKDLDriver
│   ├── DCPDPServiceProxy
│   ├── DCPEndpointV2
│   ├── H11ANEIn
│   ├── HibernationService
│   ├── IOBlockStorageDriver
│   ├── IOHDIXHDDriveOutKernel
│   ├── IOMobileFramebufferShim
│   ├── IOPCIDevice
│   ├── IOPMrootDomain
│   ├── IOPowerConnection
│   ├── IORegistryEntry
│   ├── IORootParent
│   ├── IOThunderboltControllerType5
│   ├── IOThunderboltSwitchType5
│   ├── IOUSBHostDevice
│   ├── IOUserNetworkWLAN
│   ├── IOUserService
│   └── RTBuddy
├── IODeviceTree (31 classes)  ← firmware/ACPI device tree view
│   ├── AppleA7IOPNub
│   ├── AppleANS3CGv2Controller
│   ├── AppleAOPAudioDeviceNode
│   ├── AppleARMIICDevice
│   ├── AppleARMIISDevice
│   ├── AppleARMIODevice
│   ├── AppleARMNORFlashDevice
│   ├── AppleARMPWMDevice
│   ├── AppleARMSPIDevice
│   ├── AppleARMSPMIDevice
│   ├── AppleDockChannelDevice
│   ├── AppleHIDTransportInterface
│   ├── AppleMCA2Controller_T6030
│   ├── ApplePMGRNub
│   ├── AppleSMCInterface
│   ├── AppleSPUAppInterface
│   ├── AppleSPUHIDInterface
│   ├── AppleSimpleUARTSync
│   ├── AppleSmartIODMANub
│   ├── AppleStockholmControlConfig
│   ├── AppleTypeCRetimer
│   ├── AppleUSB20XHCIARMPort
│   ├── AppleUSB30XHCIARMPort
│   ├── IODARTMapperNub
│   ├── IODTNVRAM
│   ├── IOMedia
│   ├── IOPCIDevice
│   ├── IOPlatformDevice
│   ├── IOPlatformExpertDevice
│   ├── IORegistryEntry
│   └── IOService
├── IOAudio (1 classes)  ← audio device graph
│   └── IORegistryEntry
├── IOFireWire (1 classes)  ← FireWire topology (legacy, likely empty on modern Macs)
│   └── IORegistryEntry
└── IOUSB (3 classes)  ← USB controller/device topology
    ├── AppleT8122USBXHCI
    ├── IORegistryEntry
    └── IOUSBHostDevice
```

## Design Direction

### Starting point

THe full structure of IORegistry (planes, nodes, attributes, properties) = the "nodes all the way down".

Every plane is a tree of nodes, each node has a name, class, ID, and a properties bag, and nodes recurse indefinitely. There is no other
topography, structure or perspective.

Given that, `ezio` should:

- with no arguments output a tree-style view of the 6 planes
- have a path syntax to navigate and search the node tree

### Why XPath-style

The two most powerful XPath operators map almost perfectly onto the two things `ioreg` users
actually want to do:

- `/` — navigate a known path: `IOService/J516sAP/AppleARMPE`
- `//` — search anywhere in the tree: `IOService//AppleARMCPU`

The current `ezio <pattern>` is essentially `//` already: recursive search with no path
context. Adding `/` gives you the ability to narrow scope.

### Design considerations

**The name ambiguity problem.** Multiple nodes can share the same name (e.g. all those
`AppleARMCPU` instances). XPath handles this by returning all matches, which is the right
behavior here too — `/` means "all children named X", not "the unique child named X."

**Class vs name.** Users will often want to navigate by class rather than name. XPath uses
`[@attribute=value]` predicates for this. Something like `IOService//[@class=AppleARMCPU]`
is precise but verbose. A shorthand like `IOService//*[AppleARMCPU]` might feel more natural.

**Properties.** XPath uses `@attr` for attributes. `IOService//AppleSmartBattery/@CurrentCapacity`
to pull a specific property value is elegant and composable.

**The default plane.** If IOService is the default, `ezio //AppleARMCPU` could implicitly mean
`IOService//AppleARMCPU`, keeping the common case short.

The `//` recursive operator alone covers most of what people use `grep` + `awk` for today.

### On `//` and why ezio doesn't need it

In XPath, `//` is useful when you already know the document structure well enough to say
"start from this known landmark / node." With ioreg the whole problem is that nobody knows
the structure. THat is the problem this tool solves. Dropping into the middle with `//` assumes 
knowledge most users don't have yet.

**All searches are implicitly `//` from root.** `ezio AppleARMCPU` always starts
from the top of IOService and finds it wherever it lives. The `/` path syntax is still useful
for drilling down once you've discovered something but the default search mode is always
full-tree from root.

### Mental model

- `ezio` — show me the top (planes)
- `ezio AppleARMCPU` — find this anywhere in the tree (always starts from root)
- `ezio /IOService/J516sAP` — navigate to a known location

### Draft syntax

```
ezio [path]

Path syntax:
  /                          root (IORegistry)
  /IOService                 select a plane
  /IOService/J516sAP         navigate by node name
  /IOService//*              all nodes (full tree)
  @CurrentCapacity           select a property on the matched node(s)
  /IOService//AppleSmartBattery/@CurrentCapacity    full example

Predicates (filtering):
  //node[@class=AppleARMCPU]        filter by class
  //node[@id=0x100000300]           filter by ID
  //node[contains(@name,"CPU")]     substring match on name
```

### Flags

Flags follow the curl convention: long flags are self-documenting, short flags for power users.

| Long flag      | Short | Output |
|---|---|---|
| `--children`   | `-C`  | tree view of the matched node's children |
| `--properties` | `-P`  | key-value properties bag of the matched node |

Used together (`-C -P` or `--children --properties`) both are shown.

### Default output

With no flags, `ezio <search>` shows only the matched node's identity and location —
name, class, ID, and breadcrumb path. No children, no properties. Clean and scannable,
especially when a search returns many matches. Flags are required to go deeper.
