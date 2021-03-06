////////////////////////////////////////////////////////////////////////////////
//
//  TYPHOON FRAMEWORK
//  Copyright 2013, Typhoon Framework Contributors
//  All Rights Reserved.
//
//  NOTICE: The authors permit you to use, modify, and distribute this file
//  in accordance with the terms of the license agreement accompanying it.
//
////////////////////////////////////////////////////////////////////////////////



#import "TyphoonMethod+InstanceBuilder.h"
#import "TyphoonBlockComponentFactory.h"
#import "TyphoonAssembly.h"
#import "OCLogTemplate.h"
#import "TyphoonAssembly+TyphoonAssemblyFriend.h"
#import "TyphoonAssemblyPropertyInjectionPostProcessor.h"
#import "TyphoonIntrospectionUtils.h"

@interface TyphoonComponentFactory (Private)

- (TyphoonDefinition*)definitionForKey:(NSString*)key;

- (void)loadIfNeeded;

@end

@implementation TyphoonBlockComponentFactory

- (id)asAssembly
{
    return self;
}

- (TyphoonComponentFactory*)asFactory
{
    return self;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Class Methods
//-------------------------------------------------------------------------------------------

+ (id)factoryWithAssembly:(TyphoonAssembly*)assembly
{
    return [[self alloc] initWithAssemblies:@[assembly]];
}

+ (id)factoryWithAssemblies:(NSArray*)assemblies
{
    return [[self alloc] initWithAssemblies:assemblies];
}

+ (id)factoryFromPlistInBundle:(NSBundle*)bundle
{
    TyphoonComponentFactory* result = nil;

    NSArray* assemblyNames = [self plistAssemblyNames:bundle];
    NSAssert(!assemblyNames || [assemblyNames isKindOfClass:[NSArray class]],
        @"Value for 'TyphoonInitialAssemblies' key must be array");

    if ([assemblyNames count] > 0)
    {
        NSMutableArray* assemblies = [[NSMutableArray alloc] initWithCapacity:[assemblyNames count]];
        for (NSString* assemblyName in assemblyNames)
        {
            Class cls = TyphoonClassFromString(assemblyName);
            if (!cls)
            {
                [NSException raise:NSInvalidArgumentException format:@"Can't resolve assembly for name %@",
                                                                     assemblyName];
            }
            [assemblies addObject:[cls assembly]];
        }
        result = [TyphoonBlockComponentFactory factoryWithAssemblies:assemblies];
    }

    return result;
}

+ (NSArray*)plistAssemblyNames:(NSBundle*)bundle
{
    NSArray* names = nil;

    NSDictionary* bundleInfoDictionary = [bundle infoDictionary];
#if TARGET_OS_IPHONE
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        names = bundleInfoDictionary[@"TyphoonInitialAssemblies(iPad)"];
    } else {
        names = bundleInfoDictionary[@"TyphoonInitialAssemblies(iPhone)"];
    }
#endif
    if (!names)
    {
        names = bundleInfoDictionary[@"TyphoonInitialAssemblies"];
    }

    return names;
}

//-------------------------------------------------------------------------------------------
#pragma mark - Initialization & Destruction
//-------------------------------------------------------------------------------------------

- (id)initWithAssembly:(TyphoonAssembly*)assembly
{
    return [self initWithAssemblies:@[assembly]];
}

- (id)initWithAssemblies:(NSArray*)assemblies
{
    self = [super init];
    if (self)
    {
        [self attachPostProcessor:[TyphoonAssemblyPropertyInjectionPostProcessor new]];
        for (TyphoonAssembly* assembly in assemblies)
        {
            [self buildAssembly:assembly];
        }
    }
    return self;
}

- (void)buildAssembly:(TyphoonAssembly*)assembly
{
    LogTrace(@"Building assembly: %@", NSStringFromClass([assembly class]));
    [self assertIsAssembly:assembly];

    [assembly prepareForUse];

    [self registerAllDefinitions:assembly];
}

- (void)assertIsAssembly:(TyphoonAssembly*)assembly
{
    if (![assembly isKindOfClass:[TyphoonAssembly class]]) //
    {
        [NSException raise:NSInvalidArgumentException format:@"Class '%@' is not a sub-class of %@",
                                                             NSStringFromClass([assembly class]),
                                                             NSStringFromClass([TyphoonAssembly class])];
    }
}

- (void)registerAllDefinitions:(TyphoonAssembly*)assembly
{
    NSArray* definitions = [assembly definitions];
    for (TyphoonDefinition* definition in definitions)
    {
        [self registerDefinition:definition];
    }
}


//-------------------------------------------------------------------------------------------
#pragma mark - Overridden Methods
//-------------------------------------------------------------------------------------------

- (void)forwardInvocation:(NSInvocation*)invocation
{
    NSString* componentKey = NSStringFromSelector([invocation selector]);
    LogTrace(@"Component key: %@", componentKey);

    TyphoonRuntimeArguments* args = [TyphoonRuntimeArguments argumentsFromInvocation:invocation];

    NSInvocation* internalInvocation =
        [NSInvocation invocationWithMethodSignature:[self methodSignatureForSelector:@selector(componentForKey:args:)]];
    [internalInvocation setSelector:@selector(componentForKey:args:)];
    [internalInvocation setArgument:&componentKey atIndex:2];
    [internalInvocation setArgument:&args atIndex:3];
    [internalInvocation invokeWithTarget:self];

    void* returnValue;
    [internalInvocation getReturnValue:&returnValue];
    [invocation setReturnValue:&returnValue];
}

- (NSMethodSignature*)methodSignatureForSelector:(SEL)aSelector
{
    if ([self respondsToSelector:aSelector])
    {
        return [[self class] instanceMethodSignatureForSelector:aSelector];
    }
    else
    {
        return [TyphoonIntrospectionUtils methodSignatureWithArgumentsAndReturnValueAsObjectsFromSelector:aSelector];
    }
}

@end