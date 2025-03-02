# Winter Beacon

An Objective-C implementation of a beacon client that communicates with the server using a custom binary protocol.

## Features

- Registers with the server using a unique ID
- Provides system information (hostname, username, OS version)
- SSL certificate validation bypass for development environments
- Regular ping mechanism to maintain connection with the server
- Robust error handling and retry logic
- Custom binary protocol implementation
- Graceful shutdown on Ctrl+C

## Building the Application

To build the application, run:

```bash
make
```

This will compile the source code and create an executable named `winter_beacon`.

## Running the Application

To run the application with the default server URL (https://localhost:4444):

```bash
./winter_beacon
```

To specify a custom server URL:

```bash
./winter_beacon --url=https://your-server-url.com:4444
```

For backward compatibility, you can also specify the URL as a positional argument:

```bash
./winter_beacon https://your-server-url.com:4444
```

Use the help flag to see all available options:

```bash
./winter_beacon --help
```

## Protocol Format

The beacon uses a text-based protocol to communicate with the server. Each message follows this format:

```
Version: 1
Type: 2
client_id: 9A70F94D-DDF6-4B01-B2E2-309A253C2065
hostname: macbookpro.lan
os_version: Darwin 24.1.0
username: dop
```

Where:

- `Version` specifies the protocol version (currently 1)
- `Type` indicates the type of message:
  - 2 = Init (registration)
  - 1 = Ping (status update)
- Additional key-value pairs follow, with one pair per line
- The `client_id` field is required for server to identify the beacon

The Content-Type for these messages is set to "text/plain".

## Server Endpoints

The beacon communicates with the server using two main endpoints:

- `/beacon/init` - Used for initial registration (POST)
- `/` - Used for regular status updates/pings (POST)

## Project Structure

- `main.m` - Entry point that initializes and starts the beacon
- `ZBeacon.h/m` - Main beacon class that handles registration and the ping loop
- `ZAPIClient.h/m` - API client for communicating with the server
- `ZSSLBypass.h/m` - Handles SSL certificate validation bypass
- `ZSystemInfo.h/m` - Utility class to gather system information

## Error Handling and Recovery

The beacon implements robust error handling with exponential backoff for retrying failed registration attempts. If registration fails, it will retry with increasing delay intervals up to a maximum number of retry attempts.

## Cleaning

To clean the build artifacts, run:

```bash
make clean
```
