module SyntaxHighlight.Line
    exposing
        ( Line
        , Highlight(..)
        , highlightLines
        , Fragment
        , Color(..)
        )


type alias Line =
    { fragments : List Fragment
    , highlight : Maybe Highlight
    }


type Highlight
    = Normal
    | Add
    | Delete


highlightLines : Maybe Highlight -> Int -> Int -> List Line -> List Line
highlightLines maybeHighlight start end lines =
    let
        length =
            List.length lines

        start_ =
            if start < 0 then
                length + start
            else
                start

        end_ =
            if end < 0 then
                length + end
            else
                end
    in
        List.indexedMap (highlightLinesHelp maybeHighlight start_ end_) lines


highlightLinesHelp : Maybe Highlight -> Int -> Int -> Int -> Line -> Line
highlightLinesHelp maybeHighlight start end index line =
    if index >= start && index < end then
        { line | highlight = maybeHighlight }
    else
        line


type alias Fragment =
    { text : String
    , color : Color
    , isEmphasis : Bool
    , isStrong : Bool
    }



-- Style
-- The comment say the most common uses of the color.


type Color
    = Default
    | Color1 -- Comment
    | Color2 -- Literal string, attribute value
    | Color3 -- Keyword, tag, operator symbol (=+-*/...)
    | Color4 -- Keyword, type signature, group symbol ({}(),)
    | Color5 -- Function, attribute name
    | Color6 -- Literal keyword
    | Color7 -- Argument, parameter