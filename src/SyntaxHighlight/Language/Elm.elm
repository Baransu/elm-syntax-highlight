module SyntaxHighlight.Language.Elm
    exposing
        ( parse
          -- Exposing just for tests purpose
        , toSyntax
          -- Exposing just for tests purpose
        , SyntaxType(..)
        )

import Char
import Set exposing (Set)
import Parser exposing (Parser, oneOf, zeroOrMore, oneOrMore, ignore, symbol, keyword, (|.), (|=), source, ignoreUntil, keep, Count(..), Error, map, andThen)
import SyntaxHighlight.Fragment exposing (Fragment, Color(..), normal, emphasis)
import SyntaxHighlight.Helpers exposing (isWhitespace, isSpace, isLineBreak, number, delimited)


type alias Syntax =
    ( SyntaxType, String )


type SyntaxType
    = Normal
    | Comment
    | String
    | BasicSymbol
    | GroupSymbol
    | Capitalized
    | Keyword
    | Function
    | TypeSignature
    | Space
    | LineBreak
    | Number


parse : String -> Result Error (List Fragment)
parse =
    toSyntax
        >> Result.map (List.map syntaxToFragment)


toSyntax : String -> Result Error (List Syntax)
toSyntax =
    Parser.run (lineStart functionBody [])


lineStart : (List Syntax -> Parser (List Syntax)) -> List Syntax -> Parser (List Syntax)
lineStart continueFunction revSyntaxList =
    oneOf
        [ moduleDeclaration "module" revSyntaxList
        , moduleDeclaration "import" revSyntaxList
        , portDeclaration revSyntaxList
        , oneOf [ space, comment ]
            |> andThen (\n -> continueFunction (n :: revSyntaxList))
        , lineBreak
            |> andThen (\n -> lineStart continueFunction (n :: revSyntaxList))
        , functionBodyKeyword revSyntaxList
        , variable
            |> map ((,) Function)
            |> andThen (\n -> functionSignature (n :: revSyntaxList))
        , functionBody revSyntaxList
        ]



-- Module Declaration Syntax


moduleDeclaration : String -> List Syntax -> Parser (List Syntax)
moduleDeclaration keyword revSyntaxList =
    Parser.keyword keyword
        |> andThen
            (\_ ->
                oneOf
                    [ oneOf
                        [ space
                        , comment
                        , lineBreak
                        ]
                        |> andThen
                            (\n ->
                                moduleDeclarationLoop 0
                                    (n :: ( Keyword, keyword ) :: revSyntaxList)
                            )
                    , end (( Keyword, keyword ) :: revSyntaxList)
                    , keep zeroOrMore isVariableChar
                        |> andThen
                            (\str ->
                                functionSignature
                                    (( Function, (keyword ++ str) ) :: revSyntaxList)
                            )
                    ]
            )


moduleDeclarationLoop : Int -> List Syntax -> Parser (List Syntax)
moduleDeclarationLoop nestLevel revSyntaxList =
    let
        mdl nestLevel_ head =
            moduleDeclarationLoop nestLevel_ (head :: revSyntaxList)
    in
        oneOf
            [ lineBreak
                |> andThen (\n -> lineStart (moduleDeclarationLoop nestLevel) (n :: revSyntaxList))
            , symbol "("
                |> andThen (\_ -> mdl (nestLevel + 1) ( Normal, "(" ))
            , symbol ")"
                |> andThen (\_ -> mdl (max 0 (nestLevel - 1)) ( Normal, ")" ))
            , moduleDeclarationContent nestLevel
                |> andThen (mdl nestLevel)
            , end revSyntaxList
            ]


moduleDeclarationContent : Int -> Parser Syntax
moduleDeclarationContent nestLevel =
    if nestLevel == 1 then
        let
            isSpecialChar c =
                isWhitespace c || c == '(' || c == ')' || c == ',' || c == '.' || c == '-'
        in
            oneOf
                [ space
                , comment
                , keep oneOrMore (\c -> c == '-' || c == ',' || c == '.')
                    |> map ((,) Normal)
                , source
                    (ignore (Exactly 1) Char.isUpper
                        |. ignore zeroOrMore (not << isSpecialChar)
                    )
                    |> map ((,) TypeSignature)
                , keep oneOrMore (not << isSpecialChar)
                    |> map ((,) Function)
                ]
    else
        let
            isSpecialChar c =
                isWhitespace c || c == '(' || c == ')' || c == '-'
        in
            oneOf
                [ space
                , comment
                , symbol "-" |> map (\_ -> ( Normal, "-" ))
                , Parser.keyword "exposing"
                    |> map (\_ -> ( Keyword, "exposing" ))
                , Parser.keyword "as"
                    |> map (\_ -> ( Keyword, "as" ))
                , keep oneOrMore (not << isSpecialChar)
                    |> map ((,) Normal)
                ]



-- Port Declaration


portDeclaration : List Syntax -> Parser (List Syntax)
portDeclaration revSyntaxList =
    Parser.keyword "port"
        |> andThen
            (\_ ->
                oneOf
                    [ oneOf
                        [ space
                        , comment
                        , lineBreak
                        ]
                        |> andThen (\n -> portLoop (n :: ( Keyword, "port" ) :: revSyntaxList))
                    , end (( Keyword, "port" ) :: revSyntaxList)
                    , keep zeroOrMore isVariableChar
                        |> andThen
                            (\str ->
                                functionSignature
                                    (( Function, ("port" ++ str) ) :: revSyntaxList)
                            )
                    ]
            )


portLoop : List Syntax -> Parser (List Syntax)
portLoop revSyntaxList =
    oneOf
        [ oneOf
            [ space
            , comment
            , lineBreak
            ]
            |> andThen (\n -> portLoop (n :: revSyntaxList))
        , moduleDeclaration "module" revSyntaxList
        , variable
            |> map ((,) Function)
            |> andThen (\n -> functionSignature (n :: revSyntaxList))
        , functionBody revSyntaxList
        ]



-- Function Signature


functionSignature : List Syntax -> Parser (List Syntax)
functionSignature revSyntaxList =
    oneOf
        [ symbol ":"
            |> map (always ( BasicSymbol, ":" ))
            |> andThen (\n -> functionSignatureLoop (n :: revSyntaxList))
        , space
            |> andThen (\n -> functionSignature (n :: revSyntaxList))
        , lineBreak
            |> andThen (\n -> lineStart functionSignature (n :: revSyntaxList))
        , functionBody revSyntaxList
        ]


functionSignatureLoop : List Syntax -> Parser (List Syntax)
functionSignatureLoop revSyntaxList =
    oneOf
        [ lineBreak
            |> andThen (\n -> lineStart functionSignature (n :: revSyntaxList))
        , functionSignatureContent
            |> andThen (\n -> functionSignatureLoop (n :: revSyntaxList))
        , end revSyntaxList
        ]


functionSignatureContent : Parser Syntax
functionSignatureContent =
    let
        isSpecialChar c =
            isWhitespace c || c == '(' || c == ')' || c == '-' || c == ','
    in
        oneOf
            [ space
            , comment
            , symbol "()" |> map (always ( TypeSignature, "()" ))
            , symbol "->" |> map (always ( BasicSymbol, "->" ))
            , keep oneOrMore (\c -> c == '(' || c == ')' || c == '-' || c == ',')
                |> map ((,) Normal)
            , source
                (ignore (Exactly 1) Char.isUpper
                    |. ignore zeroOrMore (not << isSpecialChar)
                )
                |> map ((,) TypeSignature)
            , keep oneOrMore (not << isSpecialChar)
                |> map ((,) Normal)
            ]



-- Function Body


functionBody : List Syntax -> Parser (List Syntax)
functionBody revSyntaxList =
    oneOf
        [ functionBodyKeyword revSyntaxList
        , functionBodyContent
            |> andThen (\n -> functionBody (n :: revSyntaxList))
        , lineBreak
            |> andThen (\n -> lineStart functionBody (n :: revSyntaxList))
        , end revSyntaxList
        ]


functionBodyContent : Parser Syntax
functionBodyContent =
    oneOf
        [ space
        , string
        , comment
        , number
            |> source
            |> map ((,) Number)
        , symbol "()"
            |> map (always ( Capitalized, "()" ))
        , basicSymbol
            |> map ((,) BasicSymbol)
        , groupSymbol
            |> map ((,) GroupSymbol)
        , capitalized
            |> map ((,) Capitalized)
        , variable
            |> map ((,) Normal)
        , weirdText
            |> map ((,) Normal)
        ]


space : Parser Syntax
space =
    ignore oneOrMore isSpace
        |> source
        |> map ((,) Space)


lineBreak : Parser Syntax
lineBreak =
    ignore oneOrMore isLineBreak
        |> source
        |> map ((,) LineBreak)


functionBodyKeyword : List Syntax -> Parser (List Syntax)
functionBodyKeyword revSyntaxList =
    functionBodyKeywords
        |> andThen
            (\kwStr ->
                oneOf
                    [ oneOf
                        [ space
                        , comment
                        , lineBreak
                        ]
                        |> andThen
                            (\n ->
                                functionBody
                                    (n :: ( Keyword, kwStr ) :: revSyntaxList)
                            )
                    , end (( Keyword, kwStr ) :: revSyntaxList)
                    , keep zeroOrMore isVariableChar
                        |> andThen
                            (\str ->
                                functionBody
                                    (( Normal, (kwStr ++ str) ) :: revSyntaxList)
                            )
                    ]
            )


functionBodyKeywords : Parser String
functionBodyKeywords =
    [ "as"
    , "where"
    , "let"
    , "in"
    , "if"
    , "else"
    , "then"
    , "case"
    , "of"
    , "type"
    , "alias"
    ]
        |> List.map (Parser.keyword >> source)
        |> oneOf


basicSymbol : Parser String
basicSymbol =
    keep oneOrMore isBasicSymbol


isBasicSymbol : Char -> Bool
isBasicSymbol c =
    Set.member c basicSymbols


basicSymbols : Set Char
basicSymbols =
    Set.fromList
        [ '|'
        , '.'
        , '='
        , '\\'
        , '/'
        , '('
        , ')'
        , '-'
        , '>'
        , '<'
        , ':'
        , '+'
        , '!'
        , '$'
        , '%'
        , '&'
        , '*'
        ]


groupSymbol : Parser String
groupSymbol =
    keep oneOrMore isGroupSymbol


isGroupSymbol : Char -> Bool
isGroupSymbol c =
    Set.member c groupSymbols


groupSymbols : Set Char
groupSymbols =
    Set.fromList
        [ ','
        , '['
        , ']'
        , '{'
        , '}'
        ]


capitalized : Parser String
capitalized =
    source <|
        ignore (Exactly 1) Char.isUpper
            |. ignore zeroOrMore isVariableChar


variable : Parser String
variable =
    source <|
        ignore (Exactly 1) Char.isLower
            |. ignore zeroOrMore isVariableChar


isVariableChar : Char -> Bool
isVariableChar c =
    not
        (isWhitespace c
            || isBasicSymbol c
            || isGroupSymbol c
            || (c == '"')
            || (c == '\'')
        )


weirdText : Parser String
weirdText =
    keep oneOrMore isVariableChar
        |> source



-- String/Char


string : Parser Syntax
string =
    oneOf
        [ tripleDoubleQuote
        , oneDoubleQuote
        , quote
        ]
        |> source
        |> map ((,) String)


oneDoubleQuote : Parser ()
oneDoubleQuote =
    delimited
        { start = "\""
        , end = "\""
        , isNestable = False
        , isEscapable = True
        }


tripleDoubleQuote : Parser ()
tripleDoubleQuote =
    delimited
        { start = "\"\"\""
        , end = "\"\"\""
        , isNestable = False
        , isEscapable = False
        }


quote : Parser ()
quote =
    delimited
        { start = "'"
        , end = "'"
        , isNestable = False
        , isEscapable = True
        }



-- Comments


comment : Parser Syntax
comment =
    oneOf
        [ inlineComment
        , multilineComment
        ]
        |> source
        |> map ((,) Comment)


inlineComment : Parser ()
inlineComment =
    symbol "--"
        |. ignore zeroOrMore (not << isLineBreak)


multilineComment : Parser ()
multilineComment =
    delimited
        { start = "{-"
        , end = "-}"
        , isNestable = True
        , isEscapable = False
        }


end : List Syntax -> Parser (List Syntax)
end revSyntaxList =
    Parser.end
        |> map (\_ -> List.reverse revSyntaxList)


syntaxToFragment : Syntax -> Fragment
syntaxToFragment ( syntaxType, text ) =
    case syntaxType of
        Normal ->
            normal Default text

        Comment ->
            normal Color1 text

        String ->
            normal Color2 text

        BasicSymbol ->
            normal Color3 text

        GroupSymbol ->
            normal Color4 text

        Capitalized ->
            normal Color6 text

        Keyword ->
            normal Color3 text

        Function ->
            normal Color5 text

        TypeSignature ->
            emphasis Color4 text

        Space ->
            normal Default text

        LineBreak ->
            normal Default text

        Number ->
            normal Color6 text