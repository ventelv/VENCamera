# Vendored Syphon

These files are a subset of [Syphon-Framework](https://github.com/Syphon/Syphon-Framework), BSD-2-Clause (see `LICENSE.txt`).

- **Upstream commit:** `f476167` (2026-09-21), branch `main`.
- **Why vendored:** Syphon has no Swift Package Manager package, and VENCamera builds with the Command Line Tools rather than Xcode.

## What's included
Only the Metal server and the messaging it needs:
- `SyphonServerBase`, `SyphonMetalServer`, `SyphonServerRendererMetal`, `SyphonServerConnectionManager`
- `SyphonMessaging`, `SyphonMessageSender`, `SyphonMessageReceiver`, `SyphonCFMessageSender`, `SyphonCFMessageReceiver`, `SyphonMessageQueue`
- `SyphonPrivate`, `SyphonDispatch`, `SyphonSubclassing.h`, `SyphonServerMetalTypes.h`
- `Syphon_Prefix.h`, copied from upstream's `Syphon_Prefix.pch`

Clients, OpenGL code and the server directory are left out.

## Changes from upstream
1. `SyphonSubclassing.h`: removed the `SyphonClientBase (SyphonSubclassing)` category and its import, because no client code is included.
2. `SyphonServerRendererMetal.m`: compiles the shaders from `SyphonMetalShaders.metal` at runtime with `newLibraryWithSource:` (the source is embedded as a string). The Command Line Tools have no Metal compiler, so no `.metallib` can be built. The shader code itself is unchanged.
3. `include/module.modulemap`: added so Swift can import the server headers.

To update, copy the same files from a newer upstream commit, reapply these three changes, and update the commit above.
