# ezio

## Install

```sh
git clone https://github.com/YOUR_USERNAME/ezio.git
cd ezio
swift build -c release
sudo cp .build/release/ezio /usr/local/bin/ezio
```

Requires macOS 13+ and Swift 5.9+.

## Description

A fast, scriptable navigator for the macOS IORegistry.

## Usage

```sh
ezio [<path>] [-h] [-i] [-P] [-C] [-p] [-S]

ARGUMENTS:
  <path>                 Path expression or bare name to search.

OPTIONS:
  -h, --help              Show help information.
  -i, --interactive       Enter interactive shell mode.
  -P, --planes            List all IORegistry planes.
  -C, --children          Show children tree.
  -p, --properties        Show properties bag.
  -S, --string            Print raw string value only (for scripting).
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
| `quit` | exit |

### Path syntax reference

| Syntax | Meaning |
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

## Methodology

The best way to use `ezio` is in a 2-phase workflow:

**DISCOVER --> COLLECT**

### DISCOVER

Find the strings you need — 3 ways.

**1. Interactive shell** - best for exploration, like `dscl` or `scutil`:

```sn
ezio -i
  > ls, cd, read, get, find
```

**2. Bare search** - matches node class (`ioreg -c`), and / or name (`ioreg -n`), and / or property key (`ioreg -k`):

```sh
ezio AppleSmartBattery          # find node, see its location
ezio AppleSmartBattery -p       # find node + show all properties
ezio AppleSmartBattery -p -C    # find node + properties + children
ezio AppleRawBatteryVoltage     # find any node that has this key
```

- `-p` shows the matched node's full properties bag — every key / value pair, i.e., "inspect this node in depth".
- `-C` additionally renders the full children tree below the matched node, i.e., "inspect this node in depth plus everything below it".

E.g., for `AppleSmartBattery`, children are typically just internal power management sub-drivers, so the difference is small.

For something like a USB hub or a GPU complex, `-C` reveals a whole subtree of nested nodes beneath it.

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

**Interactive shell**
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
  IOPlatformSerialNumber: "Z4D9WXVN5X"
  IOPlatformUUID: "1Z848BE8-E47F-5354-9D90-Z20450BE4CF9"
  IOPolledInterface: "AppleARMWatchdogTimerHibernateHandler is not serializable"
  IOServiceBusyState: 0
  IOServiceBusyTime: 159135702291
  IOServiceState: 30
  clock-frequency: <00 36 6e 01>
  compatible: <4b 35 31 36 73 41 50 00 4d 66 63 31 35 2c 37 00 ...> (25 bytes)
  config-number: <00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 ...> (64 bytes)
  country-of-origin: "CHN"
  device-tree-tag: "EmbeddedDeviceTrees-11156.81.3"
  device_type: "bootrom"
  manufacturer: "Apple Inc."
  mlb-serial-number: <46 56 39 49 38 37 30 30 46 31 51 30 30 30 30 48 ...> (32 bytes)
  model: "Mac15,7"
  model-config: "ICT;MoPED=0xDEE20C1D50321D3211624D3341F1D3B628F6C7C7"
  model-number: <4d 52 56 34 35 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  name: "device-tree"
  platform-name: <74 36 30 33 30 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  region-info: <4c 2c 2f 31 00 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  regulatory-model-number: <47 32 39 38 31 00 00 00 00 00 00 00 00 00 00 00 ...> (32 bytes)
  secure-root-prefix: "md"
  serial-number: <48 34 44 31 57 59 54 4e 36 4c 00 00 00 00 00 00 ...> (32 bytes)
  target-sub-type: "J516sAP"
  target-type: "J516s"
  time-stamp: "Wed Jan 28 20:41:33 PST 2026"
IOService/J516sAP> get IOPlatformSerialNumber
Z4D9WXVN5X
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
