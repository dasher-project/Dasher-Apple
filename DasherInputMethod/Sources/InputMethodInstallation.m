#import "InputMethodInstallation.h"
#import <Security/Security.h>
#import <os/log.h>

BOOL DasherIsBundledInputMethod(NSBundle *bundle) {
    NSURL *helpers = bundle.bundleURL.URLByDeletingLastPathComponent;
    return [helpers.lastPathComponent isEqualToString:@"Helpers"] &&
        [helpers.URLByDeletingLastPathComponent.lastPathComponent isEqualToString:@"Contents"];
}

static NSData *ValidSignatureHash(NSURL *url) {
    SecStaticCodeRef code = NULL;
    if (SecStaticCodeCreateWithPath((__bridge CFURLRef)url, kSecCSDefaultFlags, &code) != errSecSuccess) return nil;
    CFDictionaryRef details = NULL;
    NSData *hash = nil;
    if (SecStaticCodeCheckValidity(code, kSecCSStrictValidate, NULL) == errSecSuccess &&
        SecCodeCopySigningInformation(code, kSecCSDefaultFlags, &details) == errSecSuccess) {
        hash = CFBridgingRelease(details)[(__bridge NSString *)kSecCodeInfoUnique];
    }
    CFRelease(code);
    return hash;
}

static BOOL CopyInputMethod(NSBundle *bundle, NSURL *destination, NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    BOOL exists = [files fileExistsAtPath:destination.path];
    if (exists) {
        NSBundle *installed = [NSBundle bundleWithURL:destination];
        if (![installed.bundleIdentifier isEqualToString:bundle.bundleIdentifier]) return NO;
        NSData *currentHash = ValidSignatureHash(bundle.bundleURL);
        if (currentHash && [currentHash isEqualToData:ValidSignatureHash(destination)]) return YES;
    }

    NSURL *replacementFolder = [files URLForDirectory:NSItemReplacementDirectory inDomain:NSUserDomainMask
        appropriateForURL:destination.URLByDeletingLastPathComponent create:YES error:error];
    if (!replacementFolder) return NO;
    NSURL *replacement = [replacementFolder URLByAppendingPathComponent:destination.lastPathComponent];
    BOOL copied = [files copyItemAtURL:bundle.bundleURL toURL:replacement error:error];
    if (copied && exists) {
        copied = [files replaceItemAtURL:destination withItemAtURL:replacement backupItemName:nil
            options:NSFileManagerItemReplacementUsingNewMetadataOnly resultingItemURL:NULL error:error];
    } else if (copied) {
        copied = [files moveItemAtURL:replacement toURL:destination error:error];
    }
    [files removeItemAtURL:replacementFolder error:NULL];
    return copied;
}

BOOL DasherInstallInputMethod(NSBundle *bundle) {
    NSFileManager *files = NSFileManager.defaultManager;
    NSError *error = nil;
    NSURL *library = [files URLForDirectory:NSLibraryDirectory inDomain:NSUserDomainMask
        appropriateForURL:nil create:YES error:&error];
    NSURL *folder = [library URLByAppendingPathComponent:@"Input Methods" isDirectory:YES];
    NSURL *destination = [folder URLByAppendingPathComponent:bundle.bundleURL.lastPathComponent isDirectory:YES];
    if (!destination || ![files createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:&error] ||
        !CopyInputMethod(bundle, destination, &error)) {
        os_log_error(OS_LOG_DEFAULT, "Dasher input source installation failed (%{public}ld)", (long)error.code);
        return NO;
    }

    return YES;
}
