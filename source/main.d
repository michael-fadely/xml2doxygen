module main;

import std.algorithm;
import std.array;
import std.stdio;
import std.string;
import std.file;
import std.exception : enforce;
import std.xml;

void main(string[] args)
{
	foreach (string s; args[1 .. $])
	{
		try
		{
			enforce(exists(s), "File does not exist: " ~ s);

			auto text = cast(string)read(s);

			foreach (string line; convert(lineSplitter(text)))
			{
				stdout.writeln(line);
			}
		}
		catch (Exception ex)
		{
			stderr.writeln(ex.message);
		}
	}

	debug
	{
		stderr.writeln();
		stderr.writeln("[done]");
		stdin.readln();
	}
}

/**
	Gets the indentation level of an XML code documentation line.

	Params:
		str = The XML code documentation line beginning with "///".

	Returns:
		`string` of characters used to indent this line.
 */
string getIndent(string str)
{
	ptrdiff_t indentLength = str.indexOf("///");

	// there's no indentation if the first index
	// of /// is 0 or if none was found (-1)
	if (indentLength > 0)
	{
		return str[0 .. indentLength];
	}

	return null;
}

/**
	Parses an array of XML code documentation lines
	and outputs converted Doxygen code documentation.

	Params:
		docLines = Array of lines beginning with "///"

	Returns:
		Converted Doxygen code documentation.
 */
string[] parse(string[] docLines)
{
	string indent;

	auto firstDocComment = docLines.find!(x => x.canFind("///"));

	if (!firstDocComment.empty)
	{
		indent = firstDocComment.front.getIndent();
	}

	const string lineStart = indent ~ " * ";

	Appender!(string[]) result;

	// insert the first doc line.
	result.put(indent ~ "/**");

	immutable string filtered = ("<root>" ~ docLines ~ "</root>")
		.map!((string x) => x.stripLeft().replace("/// ", "").replace("///", ""))
		.array
		.join("\n");

	auto doc = new DocumentParser(filtered);

	// Source for tags:
	// https://docs.microsoft.com/en-us/cpp/ide/recommended-tags-for-documentation-comments-visual-cpp
	// Managed C++/C# specific tags are not supported.

	/// convenience template for repeat code
	template innerParser()
	{
		Appender!(string) builder;

		void innerParserInit(ElementParser parser)
		{
			parser.onStartTag["c"] = (ElementParser p)
			{
				p.onText = (string s)
				{
					builder.put(`\c ` ~ s);
				};

				p.parse();
			};

			parser.onStartTag["paramref"] = (ElementParser p)
			{
				builder.put(`\p ` ~ p.tag.attr["name"]);
			};

			parser.onStartTag["para"] = (ElementParser p)
			{
				p.onText = (string s) { builder.put(s); };
				p.parse();
			};

			e.onText = (string s)
			{
				builder.put(s);
			};
		}
	}

	/// ditto
	template outerParser(string prefix)
	{
		alias outerParser = (ElementParser e)
		{
			mixin innerParser;
			builder.put(prefix);

			innerParserInit(e);
			e.parse();

			result.put(builder.data.lineSplitter.map!((string s) => lineStart ~ s));
		};
	}

	doc.onStartTag["summary"] = outerParser!(`\brief `);
	doc.onStartTag["returns"] = outerParser!(`\return `);
	doc.onStartTag["remarks"] = outerParser!(`\remarks `);

	doc.parse();

	result.put(indent ~ " */");
	return result.data;
}

/**
	Converts a range of lines containing XML code
	documentation to Doxygen code documentation.

	Params:
		R     = Range type.
		lines = Range of lines.

	Returns:
		Array of lines containing converted documentation and code.
 */
string[] convert(R)(R lines)
{
	auto result = appender!(string[]);
	auto docStr = appender!(string[]);

	bool found;

	foreach (string line; lines)
	{
		// if we can find a line beginning documentation...
		if (line.canFind("///"))
		{
			// add to the document and continue.
			found = true;
			docStr.put(line);
			continue;
		}

		// if the line has any non-whitespace content...
		if (!line.strip().empty)
		{
			// the document building is done
			// (if started); add it to the result.
			if (found)
			{
				found = false;
				result.put(parse(docStr.data));
				docStr.clear();
			}
		}
		else if (found)
		{
			// otherwise we're handling a blank line; keep going!
			continue;
		}

		result.put(line);
	}

	if (found)
	{
		result.put(parse(docStr.data));
	}

	return result.data;
}