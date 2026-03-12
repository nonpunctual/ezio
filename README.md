# ezio

## Install

```sh
git clone https://github.com/nonpunctual/ezio.git
cd ezio
swift build -c release
sudo cp .build/release/ezio /usr/local/bin/ezio
```

Requires macOS 13+ and Swift 5.9+.

## Description

A fast, scriptable navigator for the macOS IORegistry.

## Usage

```sh
ezio [<path>] [-i] [-P] [-C] [-F] [-p] [-S] [-h] 

ARGUMENTS:

  <path>                 Path expression or bare name to search.

OPTIONS:

  -i, --interactive       Enter interactive shell mode
  -P, --planes            List all IORegistry planes
  -C, --children          Show expansion of selected node
  -F, --fold              Show folded, enumerated child nodes
  -p, --properties        Show properties bag
  -S, --string            Extract raw value without breadcrumbs
  -h, --help              Show help information
```

### Interactive shell commands

| Command | Description |
|---|---|
| `ls` | list children (numbered) |
| `cd <name\|number>` | enter child node or plane |
| `cd ..` | go up one level |
| `cd /` | return to IORegistry root |
| `info` | current node identity |
| `read` | show all properties |
| `keys` | list property key names |
| `get <key>` | show raw value of a property |
| `find <term>` | search from current node |
| `pwd` | show current path |
| `quit` | exit |

### Path syntax reference

| Syntax | Function |
|---|---|
| `ezio Name` | recursive search — matches name, class, or property key |
| `/IOService` | select a plane |
| `/IOService/J516sAP` | navigate by node name |
| `/IOService//Name` | recursive search by name (strict) |
| `/IOService//[ClassName]` | search by class (shorthand) |
| `/IOService//[@class=Name]` | search by class (explicit) |
| `/IOService//[contains(@name,"x")]` | substring match on name |
| `/IOService//[contains(@class,"x")]` | substring match on class |
| `/IOService//[@id=0x...]` | match by registry ID |
| `/IOService//Node/@key` | select a property value |
| `/IOService//Node/[n]` | select the nth child by node number - index starts at 1 |

## Methodology

The best way to use `ezio` is in a 2-phase workflow:

**DISCOVER --> COLLECT**

### DISCOVER

Find the strings you need — 3 ways.

**1. Interactive shell** - best for exploration, like `dscl` or `scutil`:

```sh
ezio -i
  > ls, cd, read, get, find
```

**2. Bare search** - matches node class (`ioreg -c`), and / or name (`ioreg -n`), and / or property key (`ioreg -k`):

```sh
ezio AppleSmartBattery              # find node, see its location
ezio AppleSmartBattery -p           # find node + show all properties
ezio AppleSmartBattery -p -C        # find node + properties + full recursive child tree
ezio AppleSmartBattery -p -C -F     # find node + properties + folded, enumerated child list
ezio AppleRawBatteryVoltage         # find any node that has this key

ezio '/IOService//J516sAP' -C -F    # list immediate children of a node, enumerated
ezio '/IOService//J516sAP/[3]'      # navigate to 3rd child by position
ezio '/IOService//J516sAP/[3]' -p   # show properties of the 3rd child
```

- `-p` — full properties bag of the matched node.
- `-C` — full recursive children tree below the matched node.
- `-C -F` — folded, enumerated list of children showing how many children each node has.

**3. Scoped search** - XPath-style path expressions:
```sh
ezio '/IOService//[AppleSmartBattery]'               # by class
ezio '/IOService//[contains(@name,"Battery")]'       # substring on name
ezio '/IOService//[contains(@class,"CPU")]'          # substring on class
ezio '/IOService//[@id=0x100000300]'                 # by registry ID
```

### COLLECT

**Parsing** - Once a node and target key / value is discovered, extract it:

```sh
% ezio '/IOService//AppleSmartBattery/@CurrentCapacity' -S
100

% ezio '/IOService//[IOPlatformExpertDevice]/@IOPlatformUUID' -S
1Z848BE8-E47F-5354-9D90-Z20450BE4CF9

% ezio '/IOService//AppleSmartBattery/@AppleRawBatteryVoltage' -S
12819

% ezio product-name -S
MacBook Pro (16-inch, Nov 2023)
```

The `-S` flag attempts to print the raw value with no formatting. `ezio` converts data values stored in the IORegistry as raw bytes to plain text.

## More examples

**Xpath-style array mapping** - see enumerated child nodes and the number of child nodes in each node below.
```sh
% ezio '/IOService//J516sAP' -C -F
J516sAP <IOPlatformExpertDevice> [0x2b6]
  IOService > Root > J516sAP
  Children (8):
    1  options                                   <IODTNVRAM>  (4 children)
    2  AppleARMPE                                <AppleARMPE>  (42 children)
    3  IOResources                               <IOResources>  (51 children)
    4  IOUserResources                           <IOUserResources>  (1 children)
    5  IOUserServer(com.apple.IOUserDockChannel  <IOUserServer>
    6  IOUserServer(com.apple.driverkit.AppleUs  <IOUserServer>
    7  IOUserServer(com.apple.bcmwlan-0x100000e  <IOUserServer>
    8  IOUserServer(com.apple.IOUserBluetoothSe  <IOUserServer>
```

```sh
% ezio '/IOService//J516sAP/[2]/@CFBundleIdentifier' -S
com.apple.driver.AppleARMPlatform
```

**Interactive shell** - example of an actual unfolded "path" with key / value extraction
```
IORegistry> ls
    1  IOService
    2  IOPower
    3  IODeviceTree
    4  IOUSB
    5  IOAudio
    6  IOFireWire
IORegistry> cd IOService
  loading IOService…
IOService> ls
    1  J516sAP                                   <IOPlatformExpertDevice>  (8 children)
IOService> cd J516sAP
IOService/J516sAP> read
  #address-cells: <02 00 00 00>
  #size-cells: <02 00 00 00>
  AAPL,phandle: <01 00 00 00>
  IOBusyInterest: "IOCommand is not serializable"
  IOConsoleSecurityInterest: "IOCommand is not serializable"
  IOGeneralInterest: "IOCommand is not serializable"
  IONWInterrupts: "IONWInterrupts"
  IOObjectRetainCount: 39
  IOPlatformSerialNumber: "Z4W9WXVN5X"
  IOPlatformUUID: "1Z848BEX-E47F-5354-8D90-Z30450BE4CG9"
  IOPolledInterface: "AppleARMWatchdogTimerHibernateHandler is not serializable"
  IOServiceBusyState: 0
  IOServiceBusyTime: 159135702291
  IOServiceState: 30
  clock-frequency: <00 36 6e 01>
  compatible: <4b 35 32 36 53 41 50 00 4d 66 73 31 35 2c 37 00 ...> (25 bytes)
  config-number: <00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ...> (64 bytes)
  country-of-origin: "CHN"
  device-tree-tag: "EmbeddedDeviceTrees-11156.81.3"
  device_type: "bootrom"
  manufacturer: "Apple Inc."
  mlb-serial-number: <46 56 39 39 38 31 33 30 46 31 59 30 30 30 30 48 ...> (32 bytes)
  model: "Mac15,7"
  model-config: "ICT;MoPED=0xDEE20C1D51321D3211724D3342F1D3B628F6C7C7"
  model-number: <4d 52 59 34 31 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  name: "device-tree"
  platform-name: <54 16 70 33 39 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  region-info: <8c 1c 2c 31 00 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  regulatory-model-number: <41 32 39 38 31 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  secure-root-prefix: "md"
  serial-number: <48 34 45 31 59 59 54 4e 36 4c 00 00 00 00 00 00 ...> (32 bytes)
  target-sub-type: "J516sAP"
  target-type: "J516s"
  time-stamp: "Wed Jan 28 20:41:33 PST 2026"
IOService/J516sAP> get IOPlatformSerialNumber
Z4W9WXVN5X
```

**Scripting** - `ezio` is a drop-in replacement for `ioreg | PlistBuddy` pipelines:

```sh
# Before
model="$(/usr/libexec/PlistBuddy -c 'print 0:product-name' /dev/stdin <<< "$(/usr/sbin/ioreg -ar -k product-name)")"

# After
model="$(ezio product-name -S)"
```

```sh
# Before
UUID="$(/usr/libexec/PlistBuddy -c 'print 0:IOPlatformUUID' /dev/stdin <<< "$(/usr/sbin/ioreg -ar -d1 -k IOPlatformUUID)")"

# After
UUID="$(ezio '/IOService//[IOPlatformExpertDevice]/@IOPlatformUUID' -S)"
```



## License

MIT
