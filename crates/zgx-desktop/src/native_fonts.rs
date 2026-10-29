//! The fonts an app brings (`Application::font`), registered with Core Text
//! for this process (macOS): its native views find them by name as they
//! find the system's, so a terminal configured with the app's monospace
//! face (`font-family = Geist Mono`) draws in it.
use std::ffi::c_void;

#[link(name = "CoreFoundation", kind = "framework")]
unsafe extern "C" {
    fn CFDataCreate(allocator: *const c_void, bytes: *const u8, length: isize) -> *const c_void;
    fn CFRelease(cf: *const c_void);
}
#[link(name = "CoreGraphics", kind = "framework")]
unsafe extern "C" {
    fn CGDataProviderCreateWithCFData(data: *const c_void) -> *const c_void;
    fn CGDataProviderRelease(provider: *const c_void);
    fn CGFontCreateWithDataProvider(provider: *const c_void) -> *const c_void;
    fn CGFontRelease(font: *const c_void);
}
#[link(name = "CoreText", kind = "framework")]
unsafe extern "C" {
    fn CTFontManagerRegisterGraphicsFont(font: *const c_void, error: *mut *const c_void) -> bool;
}

/// Register the font in `bytes` for this process; whether Core Text took
/// it (a family the system has already, or bytes it cannot read, it
/// declines, and the system's stays).
pub(crate) fn register(bytes: &[u8]) -> bool {
    let Ok(length) = isize::try_from(bytes.len()) else {
        return false;
    };
    // SAFETY: Core Foundation, Core Graphics and Core Text's C API with
    // their declared types. `CFDataCreate` copies `bytes`; each object made
    // here is checked non-null and released once after use (the font
    // manager keeps its own reference to what it registers); `error` is a
    // writable local, its error (owned, Create rule) released.
    unsafe {
        let data = CFDataCreate(std::ptr::null(), bytes.as_ptr(), length);
        if data.is_null() {
            return false;
        }
        let provider = CGDataProviderCreateWithCFData(data);
        CFRelease(data);
        if provider.is_null() {
            return false;
        }
        let font = CGFontCreateWithDataProvider(provider);
        CGDataProviderRelease(provider);
        if font.is_null() {
            return false;
        }
        let mut error: *const c_void = std::ptr::null();
        let registered = CTFontManagerRegisterGraphicsFont(font, &mut error);
        if !error.is_null() {
            CFRelease(error);
        }
        CGFontRelease(font);
        registered
    }
}

#[cfg(test)]
mod tests {
    #[test]
    fn a_bundled_font_registers_and_garbage_does_not() {
        let geist = include_bytes!("../examples/support/fonts/GeistMonoVariable.ttf");
        // Once for the process: a second time it is already there.
        let first = super::register(geist);
        assert!(first || !super::register(geist));
        assert!(!super::register(b"not a font"));
    }
}
