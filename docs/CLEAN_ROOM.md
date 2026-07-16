# Clean-room boundary

YTKACE is an independent implementation.

The reference binary and decompilation were used to identify YouTube class
names, selector names, preference names, and user-visible behavior. No
decompiled function body, obfuscation, server activation logic, binary object,
resource bundle, image, audio file, or localization table is included.

YTKACE uses its own control flow, data models, networking, settings
controllers, download manager, Mach-O tooling, and runtime-hook registry.
Interface icons come from SF Symbols. The Premium logo option asks YouTube's
own installed resource bundle for YouTube's own Premium logo.

The following reference behavior is intentionally excluded:

- License and activation checks
- Installation statistics
- Analytics and telemetry
- Automatic updates
- Anti-debugging
- Frida detection
- Reference project links
- Reference branding and credits

The YTKPlus.bundle directory is research material only and must never be copied
into a release.
