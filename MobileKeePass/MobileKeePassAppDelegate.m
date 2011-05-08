/*
 * Copyright 2011 Jason Rush and John Flanagan. All rights reserved.
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

#import <AudioToolbox/AudioToolbox.h>
#import "MobileKeePassAppDelegate.h"
#import "FileViewController.h"
#import "PasswordEntryController.h"
#import "SettingsViewController.h"
#import "SFHFKeychainUtils.h"

#define TIME_INTERVAL_BEFORE_PIN 0

@implementation MobileKeePassAppDelegate

@synthesize databaseDocument;

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    // Initialize the images array
    int i;
    for (i = 0; i < 70; i++) {
        images[i] = nil;
    }
    
    databaseDocument = nil;
    
    // Set the user defaults
    NSDictionary *defaults = [NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[NSNumber numberWithBool:YES], nil] forKeys:[NSArray arrayWithObjects:@"hidePasswords", nil]];
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    [userDefaults registerDefaults:defaults];
    
    // Create the root view
    groupViewController = [[GroupViewController alloc] initWithStyle:UITableViewStylePlain];
    groupViewController.title = @"KeePass";
    
    UIBarButtonItem *openButton = [[UIBarButtonItem alloc] initWithTitle:@"Open" style:UIBarButtonItemStyleBordered target:self action:@selector(openPressed:)];
    groupViewController.navigationItem.rightBarButtonItem = openButton;
    [openButton release];
    
    UIBarButtonItem *settingsButton = [[UIBarButtonItem alloc] initWithTitle:@"Settings" style:UIBarButtonItemStyleBordered target:self action:@selector(settingsPressed:)];
    groupViewController.navigationItem.leftBarButtonItem = settingsButton;
    [settingsButton release];
    
    // Create the navigation controller
    navigationController = [[UINavigationController alloc] initWithRootViewController:groupViewController];

    // Create the window
    window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    window.rootViewController = navigationController;
    [window makeKeyAndVisible];
    
    [self openLastDatabase];
    
    return YES;
}

- (void)dealloc {
    int i;
    for (i = 0; i < 70; i++) {
        [images[i] release];
    }
    [databaseDocument release];
    [groupViewController release];
    [navigationController release];
    [window release];
    [super dealloc];
}

- (void)applicationWillResignActive:(UIApplication *)application {
    // Save the database document
    [databaseDocument save];
    
    // Store the current time as when the application exited
    NSDate *currentTime = [NSDate date];
    [[NSUserDefaults standardUserDefaults] setValue:currentTime forKey:@"exitTime"];
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
    if (![userDefaults boolForKey:@"pinEnabled"]) {
        return;
    }

    // Get the time when the application last exited
    NSDate *exitTime = [userDefaults valueForKey:@"exitTime"];
    if (exitTime == nil) {
        return;
    }
    
    NSTimeInterval timeInterval = [exitTime timeIntervalSinceNow];
    if (timeInterval < -TIME_INTERVAL_BEFORE_PIN) {
        // Present the pin view
        PinViewController *pinViewController = [[PinViewController alloc] init];
        pinViewController.delegate = self;
        [window.rootViewController presentModalViewController:pinViewController animated:YES];
        [pinViewController release];
    }
}

-(BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {

    //Prevent PIN view from showing by deleting exitTime
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:@"exitTime"];

    [self closeDatabase];
      
    //Retrieve document directory
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];

    NSString *filename = [url lastPathComponent];
    
    NSURL *newUrl = [NSURL fileURLWithPath:[documentsDirectory stringByAppendingPathComponent:filename]];
    
    //Move input file into documents directory
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    [fileManager removeItemAtURL:newUrl error:nil];
    [fileManager moveItemAtURL:url toURL:newUrl error:nil];
    [fileManager removeItemAtPath:[documentsDirectory stringByAppendingPathComponent:@"Inbox"] error:nil];
    [fileManager release];
    
    //Use FileViewController to handle opening the new file
    FileViewController *fileViewController = [[FileViewController alloc] init];
    fileViewController.selectedFile = filename;
    
    PasswordEntryController *passwordEntryController = [[PasswordEntryController alloc] init];
    passwordEntryController.delegate = fileViewController;
    [fileViewController release];
    
    [window.rootViewController presentModalViewController:passwordEntryController animated:YES];
    [passwordEntryController release];

    return YES;
}

- (DatabaseDocument*)databaseDocument {
    return databaseDocument;
}

- (void)setDatabaseDocument:(DatabaseDocument *)newDatabaseDocument {
    databaseDocument = [newDatabaseDocument retain];
    groupViewController.group = [databaseDocument.database rootGroup];
}

- (UIImage*)loadImage:(int)index {
    if (images[index] == nil) {
        NSString *imagePath = [[NSBundle mainBundle] pathForResource:[NSString stringWithFormat:@"%d", index] ofType:@"png"];
        images[index] = [[UIImage imageWithContentsOfFile:imagePath] retain];
    }

    return images[index];
}

- (void)pinViewController:(PinViewController *)controller pinEntered:(NSString *)pin {
    NSError *error;
    NSString *validPin = [SFHFKeychainUtils getPasswordForUsername:@"PIN" andServiceName:@"net.fizzawizza.MobileKeePass" error:&error];
    if (error != nil || validPin == nil) {
        // TODO error/no pin, close database
        return;
    }
    
    if ([pin isEqualToString:validPin]) {
        [controller dismissModalViewControllerAnimated:YES];
    } else {
        // Vibrate to signify they are a bad user
        AudioServicesPlaySystemSound(kSystemSoundID_Vibrate);
        
        controller.string = @"Incorrect PIN";
        [controller clearEntry];
    }
}

- (void)pinViewControllerCancelButtonPressed:(PinViewController *)controller {
    NSString* title = @"Canceling PIN entry will lock active database";
    
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:title delegate:self cancelButtonTitle:@"Close Database" destructiveButtonTitle:nil otherButtonTitles:@"Try Again", nil];
    actionSheet.actionSheetStyle = UIActivityIndicatorViewStyleGray;
    [actionSheet showInView:window];
    [actionSheet release];
}

- (void)closeDatabase {
    [navigationController popToRootViewControllerAnimated:NO];

    groupViewController.group = nil;
}

- (void)openLastDatabase {
    // Get the last filename
    NSUserDefaults* userDefaults = [NSUserDefaults standardUserDefaults];
    NSString *lastFilename = [userDefaults stringForKey:@"lastFilename"];
    if (lastFilename == nil) {
        return;
    }
    
    // Load the password from the keychain
    NSError *error;
    NSString *password = [SFHFKeychainUtils getPasswordForUsername:lastFilename andServiceName:@"net.fizzawizza.MobileKeePass" error:&error];
    if (error != nil || password == nil) {
        return;
    }
    
    // Load the database
    DatabaseDocument *dd = [[DatabaseDocument alloc] init];
    enum DatabaseError databaseError = [dd open:lastFilename password:password];
    if (databaseError == NO_ERROR) {
        self.databaseDocument = dd;
    }
    
    [dd release];
}

-(void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex {
    if (buttonIndex == actionSheet.cancelButtonIndex) {
        [self closeDatabase];
        [[NSUserDefaults standardUserDefaults] setValue:@"" forKey:@"lastFilename"];
        [window.rootViewController dismissModalViewControllerAnimated:YES];        
    }
}

- (void)openPressed:(id)sender {
    FileViewController *fileViewController = [[FileViewController alloc] initWithStyle:UITableViewStylePlain];
    
    // Push the FileViewController onto the view stack
    [navigationController pushViewController:fileViewController animated:YES];
    [fileViewController release];
}

- (void)settingsPressed:(id)sender {
    SettingsViewController *settingsViewController = [[SettingsViewController alloc] initWithStyle:UITableViewStyleGrouped];
    
    [navigationController pushViewController:settingsViewController animated:YES];
    [settingsViewController release];
}

@end
