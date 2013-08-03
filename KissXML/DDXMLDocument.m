#import "DDXMLPrivate.h"
#import "NSString+DDXML.h"

#import <libxml/parser.h>
#import <libxml/valid.h>
#import <libxml/xmlschemas.h>


/**
 * Welcome to KissXML.
 * 
 * The project page has documentation if you have questions.
 * https://github.com/robbiehanson/KissXML
 * 
 * If you're new to the project you may wish to read the "Getting Started" wiki.
 * https://github.com/robbiehanson/KissXML/wiki/GettingStarted
 * 
 * KissXML provides a drop-in replacement for Apple's NSXML class cluster.
 * The goal is to get the exact same behavior as the NSXML classes.
 * 
 * For API Reference, see Apple's excellent documentation,
 * either via Xcode's Mac OS X documentation, or via the web:
 * 
 * https://github.com/robbiehanson/KissXML/wiki/Reference
**/

@implementation DDXMLDocument

/**
 * Returns a DDXML wrapper object for the given primitive node.
 * The given node MUST be non-NULL and of the proper type.
**/
+ (id)nodeWithDocPrimitive:(xmlDocPtr)doc owner:(DDXMLNode *)owner
{
	return [[[DDXMLDocument alloc] initWithDocPrimitive:doc owner:owner] autorelease];
}

- (id)initWithDocPrimitive:(xmlDocPtr)doc owner:(DDXMLNode *)inOwner
{
	self = [super initWithPrimitive:(xmlKindPtr)doc owner:inOwner];
	return self;
}

+ (id)nodeWithPrimitive:(xmlKindPtr)kindPtr owner:(DDXMLNode *)owner
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes
	NSAssert(NO, @"Use nodeWithDocPrimitive:owner:");
	
	return nil;
}

- (id)initWithPrimitive:(xmlKindPtr)kindPtr owner:(DDXMLNode *)inOwner
{
	// Promote initializers which use proper parameter types to enable compiler to catch more mistakes.
	NSAssert(NO, @"Use initWithDocPrimitive:owner:");
	
	[self release];
	return nil;
}

/**
 * Initializes and returns a DDXMLDocument object created from an NSData object.
 * 
 * Returns an initialized DDXMLDocument object, or nil if initialization fails
 * because of parsing errors or other reasons.
**/
- (id)initWithXMLString:(NSString *)string options:(NSUInteger)mask error:(NSError **)error
{
	return [self initWithData:[string dataUsingEncoding:NSUTF8StringEncoding]
	                  options:mask
	                    error:error];
}

/**
 * Initializes and returns a DDXMLDocument object created from an NSData object.
 * 
 * Returns an initialized DDXMLDocument object, or nil if initialization fails
 * because of parsing errors or other reasons.
**/
- (id)initWithData:(NSData *)data options:(NSUInteger)mask error:(NSError **)error
{
	if (data == nil || [data length] == 0)
	{
		if (error) *error = [NSError errorWithDomain:@"DDXMLErrorDomain" code:0 userInfo:nil];
		
		[self release];
		return nil;
	}
	
	// Even though xmlKeepBlanksDefault(0) is called in DDXMLNode's initialize method,
	// it has been documented that this call seems to get reset on the iPhone:
	// http://code.google.com/p/kissxml/issues/detail?id=8
	// 
	// Therefore, we call it again here just to be safe.
	xmlKeepBlanksDefault(0);
	
	xmlDocPtr doc = xmlParseMemory([data bytes], [data length]);
	if (doc == NULL)
	{
		if (error) *error = [NSError errorWithDomain:@"DDXMLErrorDomain" code:1 userInfo:nil];
		
		[self release];
		return nil;
	}
	
	return [self initWithDocPrimitive:doc owner:nil];
}

- (id)initWithRootElement:(DDXMLElement *)element;
{
	if (element == nil)
	{
		[super dealloc];
		return nil;
	}
	
	xmlDocPtr doc = xmlNewDoc((const xmlChar *)"1.0");
	if (doc == NULL)
	{
		[super dealloc];
		return nil;
	}
	
	xmlNodePtr primitive = [element primitive];
	xmlDocSetRootElement(doc, primitive);
	[element setOwner:self];
	return [self initWithDocPrimitive:doc owner:nil];
}

/**
 * Returns the root element of the receiver.
**/
- (DDXMLElement *)rootElement
{
#if DDXML_DEBUG_MEMORY_ISSUES
	DDXMLNotZombieAssert();
#endif
	
	xmlDocPtr doc = (xmlDocPtr)genericPtr;
	
	// doc->children is a list containing possibly comments, DTDs, etc...
	
	xmlNodePtr rootNode = xmlDocGetRootElement(doc);
	
	if (rootNode != NULL)
		return [DDXMLElement nodeWithElementPrimitive:rootNode owner:self];
	else
		return nil;
}

- (NSData *)XMLData
{
	// Zombie test occurs in XMLString
	
	return [[self XMLString] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSData *)XMLDataWithOptions:(NSUInteger)options
{
	// Zombie test occurs in XMLString
	
	return [[self XMLStringWithOptions:options] dataUsingEncoding:NSUTF8StringEncoding];
}


// This is originally from http://wiki.njh.eu/XML-Schema_validation_with_libxml2
int is_valid(const xmlDocPtr doc, const char *schema_filename)
{
	xmlDocPtr schema_doc = xmlReadFile(schema_filename, NULL, XML_PARSE_NONET);
	
	if (schema_doc == NULL)
	{
		/* the schema cannot be loaded or is not well-formed */
        return -1;
    }
	
    xmlSchemaParserCtxtPtr parser_ctxt = xmlSchemaNewDocParserCtxt(schema_doc);
	
	if (parser_ctxt == NULL)
	{
		/* unable to create a parser context for the schema */
		xmlFreeDoc(schema_doc);
		return -2;
	}
	
	xmlSchemaPtr schema = xmlSchemaParse(parser_ctxt);
	
	if (schema == NULL)
	{
		/* the schema itself is not valid */
		xmlSchemaFreeParserCtxt(parser_ctxt);
		xmlFreeDoc(schema_doc);
		return -3;
	}
	
	xmlSchemaValidCtxtPtr valid_ctxt = xmlSchemaNewValidCtxt(schema);
	
	if (valid_ctxt == NULL)
	{
		/* unable to create a validation context for the schema */
		xmlSchemaFree(schema);
		xmlSchemaFreeParserCtxt(parser_ctxt);
		xmlFreeDoc(schema_doc);
		return -4; 
	}
	
	int status = xmlSchemaValidateDoc(valid_ctxt, doc);
	int is_valid = (status == 0);
	xmlSchemaFreeValidCtxt(valid_ctxt);
	xmlSchemaFree(schema);
	xmlSchemaFreeParserCtxt(parser_ctxt);
	xmlFreeDoc(schema_doc);
	
	/* force the return value to be non-negative on success */
	return is_valid ? 1 : 0;
}


- (BOOL)validateAndReturnError:(NSError**)error
{
	// libxml2 doesn't seem to like xsi:schemaLocation in the root element. We detach it from the node during validation.
	DDXMLAttributeNode *schemaLocation = (DDXMLAttributeNode*)[[self rootElement] attributeForName:@"xsi:schemaLocation"];
	[[schemaLocation retain] autorelease];
	[schemaLocation detach];
	NSArray *pairs = [[schemaLocation stringValue] componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	const char *schema_filename = NULL;
	
	if ([pairs count] > 1)
	{
		schema_filename = [[pairs objectAtIndex:1] cStringUsingEncoding:NSUTF8StringEncoding];
	}
	
	BOOL isValid = is_valid([self primitive], schema_filename) == 1;
	
	if (schemaLocation != nil)
	{
		[[self rootElement] addAttribute:schemaLocation];
	}
	
	return isValid;
}


@end
