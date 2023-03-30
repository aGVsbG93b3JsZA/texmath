{-# LANGUAGE GeneralizedNewtypeDeriving, ViewPatterns, GADTs, OverloadedStrings #-}
{-
Copyright (C) 2023 John MacFarlane <jgm@berkeley.edu>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

-}

module Text.TeXMath.Writers.Typst (writeTypst) where

import Data.List (transpose)
import qualified Data.Map as M
import qualified Data.Text as T
import Text.TeXMath.Types
import qualified Text.TeXMath.Shared as S
import Data.Generics (everywhere, mkT)
import Data.Text (Text)
import Data.Char (isDigit, isAlpha)

-- import Debug.Trace
-- tr' x = trace (show x) x

-- | Transforms an expression tree to equivalent Typst
writeTypst :: DisplayType -> [Exp] -> Text
writeTypst dt exprs =
  T.unwords $ map writeExp $ everywhere (mkT $ S.handleDownup dt) exprs

writeExps :: [Exp] -> Text
writeExps = T.intercalate " " . map writeExp

inParens :: Text -> Text
inParens s = "(" <> s <> ")"

inQuotes :: Text -> Text
inQuotes s = "\"" <> s <> "\""

esc :: Text -> Text
esc t =
  if T.any needsEscape t
     then T.concatMap escapeChar t
     else t
  where
    escapeChar c
      | needsEscape c = "\\" <> T.singleton c
      | otherwise = T.singleton c
    needsEscape '[' = True
    needsEscape ']' = True
    needsEscape '|' = True
    needsEscape '#' = True
    needsEscape '$' = True
    needsEscape '(' = True
    needsEscape ')' = True
    needsEscape '_' = True
    needsEscape _ = False

writeExpS :: Exp -> Text
writeExpS (EGrouped es) = "(" <> writeExps es <> ")"
writeExpS e =
  case writeExp e of
    t | T.all (\c -> isDigit c || c == '.') t -> t
      | T.all (\c -> isAlpha c || c == '.') t -> t
      | otherwise -> "(" <> t <> ")"

writeExpB :: Exp -> Text
writeExpB e =
  case writeExp e of
    "" -> "zws"
    t -> t

writeExp :: Exp -> Text
writeExp (ENumber s) = s
writeExp (ESymbol _t s) =
  maybe (esc s) id $ M.lookup s typstSymbols
writeExp (EIdentifier s) =
  if T.length s == 1
     then writeExp (ESymbol Ord s)
     else inQuotes s
writeExp (EMathOperator s)
  | s `elem` ["arccos", "arcsin", "arctan", "arg", "cos", "cosh",
              "cot", "ctg", "coth", "csc", "deg", "det", "dim", "exp",
              "gcd", "hom", "mod", "inf", "ker", "lg", "lim", "ln",
              "log", "max", "min", "Pr", "sec", "sin", "sinh", "sup",
              "tan", "tg", "tanh", "liminf", "and", "limsup"]
    = s
  | otherwise = "\"" <> s <> "\""
writeExp (EGrouped es) = writeExps es
writeExp (EFraction _fractype e1 e2) =
  case (e1, e2) of
    (EGrouped _, _) -> "frac(" <> writeExp e1 <> ", " <> writeExp e2 <> ")"
    (_, EGrouped _) -> "frac(" <> writeExp e1 <> ", " <> writeExp e2 <> ")"
    _ -> writeExp e1 <> " / " <> writeExp e2
writeExp (ESub b e1) = writeExpB b <> "_" <> writeExpS e1
writeExp (ESuper b e1) = writeExpB b <> "^" <> writeExpS e1
writeExp (ESubsup b e1 e2) = writeExpB b <> "_" <> writeExpS e1 <>
                                           "^" <> writeExpS e2
writeExp (EOver _convertible b e1) =
  case e1 of
    ESymbol Accent "`" -> "grave" <> inParens (writeExp b)
    ESymbol Accent "\xb4" -> "acute" <> inParens (writeExp b)
    ESymbol Accent "^" -> "hat" <> inParens (writeExp b)
    ESymbol Accent "~" -> "tilde" <> inParens (writeExp b)
    ESymbol Accent "\xaf" -> "macron" <> inParens (writeExp b)
    ESymbol Accent "\x2d8" -> "breve" <> inParens (writeExp b)
    ESymbol Accent "." -> "dot" <> inParens (writeExp b)
    ESymbol Accent "\xa8" -> "diaer" <> inParens (writeExp b)
    ESymbol Accent "\x2218" -> "circle" <> inParens (writeExp b)
    ESymbol Accent "\x2dd" -> "acute.double" <> inParens (writeExp b)
    ESymbol Accent "\x2c7" -> "caron" <> inParens (writeExp b)
    ESymbol Accent "\x2192" -> "->" <> inParens (writeExp b)
    ESymbol Accent "\x2190" -> "<-" <> inParens (writeExp b)
    ESymbol TOver "\9182" -> "overbrace(" <> writeExp b <> ")"
    ESymbol TOver "\9140" -> "overbracket(" <> writeExp b <> ")"
    _ -> writeExpB b <> "^" <> writeExpS e1
writeExp (EUnder _convertible b e1) =
  case e1 of
    ESymbol TUnder "_" -> "underline(" <> writeExp b <> ")"
    ESymbol TUnder "\9182" -> "underbrace(" <> writeExp b <> ")"
    ESymbol TUnder "\9140" -> "underbracket(" <> writeExp b <> ")"
    _ -> writeExpB b <> "_" <> writeExpS e1
writeExp (EUnderover convertible b e1 e2) =
  case (e1, e2) of
    (_, ESymbol Accent _) -> writeExp (EUnder convertible (EOver False b e2) e1)
    (_, ESymbol TOver _) -> writeExp (EUnder convertible (EOver False b e2) e1)
    (ESymbol TUnder _, _) -> writeExp (EOver convertible (EUnder False b e1) e2)
    _ -> writeExpB b <> "_" <> writeExpS e1 <> "^" <> writeExpS e2
writeExp (ESqrt e) = "sqrt(" <> writeExp e <> ")"
writeExp (ERoot i e) = "root(" <> writeExp i <> ", " <> writeExp e <> ")"
writeExp (ESpace width) =
  case (floor (width * 18) :: Int) of
    0 -> "zws"
    3 -> "thin"
    4 -> "med"
    6 -> "thick"
    18 -> "quad"
    n -> "#h(" <> tshow (n `div` 18) <> "em)"
writeExp (EText ttype s) =
  case ttype of
       TextNormal -> "upright" <> inParens (inQuotes s)
       TextItalic -> "italic" <> inParens (inQuotes s)
       TextBold   -> "bold" <> inParens (inQuotes s)
       TextBoldItalic -> "bold" <> inParens ("italic" <> inParens (inQuotes s))
       TextMonospace -> "mono" <> inParens (inQuotes s)
       TextSansSerif -> "sans" <> inParens (inQuotes s)
       TextDoubleStruck -> "bb" <> inParens (inQuotes s)
       TextScript -> "cal" <> inParens (inQuotes s)
       TextFraktur -> "frak" <> inParens (inQuotes s)
       TextSansSerifBold -> "bold" <> inParens ("sans" <> inParens (inQuotes s))
       TextSansSerifBoldItalic -> "bold" <>
         inParens ("italic" <> inParens ("sans" <> inParens (inQuotes s)))
       TextBoldScript -> "bold" <> inParens ("cal" <> inParens (inQuotes s))
       TextBoldFraktur -> "bold" <> inParens ("frak" <> inParens (inQuotes s))
       TextSansSerifItalic -> "italic" <>
          inParens ("sans" <> inParens (inQuotes s))
writeExp (EStyled ttype es) =
  let contents = writeExps es
  in case ttype of
       TextNormal -> "upright" <> inParens contents
       TextItalic -> "italic" <> inParens contents
       TextBold   -> "bold" <> inParens contents
       TextBoldItalic -> "bold" <> inParens ("italic" <> inParens contents)
       TextMonospace -> "mono" <> inParens contents
       TextSansSerif -> "sans" <> inParens contents
       TextDoubleStruck -> "bb" <> inParens contents
       TextScript -> "cal" <> inParens contents
       TextFraktur -> "frak" <> inParens contents
       TextSansSerifBold -> "bold" <> inParens ("sans" <> inParens contents)
       TextSansSerifBoldItalic -> "bold" <>
         inParens ("italic" <> inParens ("sans" <> inParens contents))
       TextBoldScript -> "bold" <> inParens ("cal" <> inParens contents)
       TextBoldFraktur -> "bold" <> inParens ("frak" <> inParens contents)
       TextSansSerifItalic -> "italic" <> inParens ("sans" <> inParens contents)
writeExp (EBoxed e) = "#box([" <> writeExp e <> "])"
writeExp (EPhantom e) = "#hide[" <> writeExp e <> "]"
writeExp (EScaled size e) =
  "#scale(x: " <> tshow (floor (100 * size) :: Int) <>
          "%, y: " <> tshow (floor (100 * size) :: Int) <>
          "%)[" <> writeExp e <> "]"
writeExp (EDelimited "(" ")" [Right (EArray _aligns rows)])
  | all (\row -> length row == 1) rows = -- vector
  "vec(" <> mkArray (transpose rows) <> ")"
writeExp (EDelimited "(" ")" [Right (EArray _aligns [[xs],[ys]])]) =
  "binom(" <> writeExps xs <> ", " <> writeExps ys <> ")"
writeExp (EDelimited "(" ")" [Right (EArray _aligns rows)]) =
  "mat(delim: \"(\", " <> mkArray rows <> ")"
writeExp (EDelimited "[" "]" [Right (EArray _aligns rows)]) =
  "mat(delim: \"[\", " <> mkArray rows <> ")"
writeExp (EDelimited "{" "}" [Right (EArray _aligns rows)]) =
  "mat(delim: \"{\", " <> mkArray rows <> ")"
writeExp (EDelimited "|" "|" [Right (EArray _aligns rows)]) =
  "mat(delim: \"|\", " <> mkArray rows <> ")"
writeExp (EDelimited "||" "||" [Right (EArray _aligns rows)]) =
  "mat(delim: \"||\", " <> mkArray rows <> ")"
writeExp (EDelimited "\x2223" "\x2223" [Right (EArray _aligns rows)]) =
  "mat(delim: \"||\", " <> mkArray rows <> ")"
writeExp (EDelimited "\x2225" "\x2225" [Right (EArray _aligns rows)]) =
  "mat(delim: \"||\", " <> mkArray rows <> ")"
writeExp (EDelimited op "" [Right (EArray [AlignLeft, AlignLeft] rows)]) =
  "cases" <> inParens("delim: " <> inQuotes op <> mconcat (map toCase rows))
   where toCase = (", " <>) . T.intercalate " & " . map writeExps
writeExp (EDelimited open close es) =
  if isDelim open && isDelim close
     then "lr" <> inParens (open <> body <> close)
     else esc open <> body <> esc close
  where fromDelimited (Left e)  = e
        fromDelimited (Right e) = writeExp e
        isDelim c = c `elem` ["(",")","[","]","{","}","|","||"]
        body = T.unwords (map fromDelimited es)
writeExp (EArray _aligns rows)
  = T.intercalate "\\\n" $ map mkRow rows
     where mkRow = T.intercalate " & " . map writeExps

mkArray :: [[[Exp]]] -> Text
mkArray rows =
  T.intercalate "; " $ map mkRow rows
 where
   mkRow = T.intercalate ", " . map mkCell
   mkCell = writeExps

tshow :: Show a => a -> Text
tshow = T.pack . show

typstSymbols :: M.Map Text Text
typstSymbols = M.fromList
  [ ("\x1d538","AA")
  , ("\x391","Alpha")
  , ("\x1d539","BB")
  , ("\x392","Beta")
  , ("\x2102","CC")
  , ("\x3A7","Chi")
  , ("\x1d53b","DD")
  , ("\x394","Delta")
  , ("\x1d53c","EE")
  , ("\x395","Epsilon")
  , ("\x397","Eta")
  , ("\x1d53d","FF")
  , ("\x1d53e","GG")
  , ("\x393","Gamma")
  , ("\x210d","HH")
  , ("\x1d540","II")
  , ("\x2111","Im")
  , ("\x399","Iota")
  , ("\x1d541","JJ")
  , ("\x1d542","KK")
  , ("\x3CF","Kai")
  , ("\x39A","Kappa")
  , ("\x1d543","LL")
  , ("\x39B","Lambda")
  , ("\x1d544","MM")
  , ("\x39C","Mu")
  , ("\x2115","NN")
  , ("\x39D","Nu")
  , ("\x1d546","OO")
  , ("\x3A9","Omega")
  , ("\x39F","Omicron")
  , ("\x2119","PP")
  , ("\x3A6","Phi")
  , ("\x3A0","Pi")
  , ("\x3A8","Psi")
  , ("\x211a","QQ")
  , ("\x211d","RR")
  , ("\x211c","Re")
  , ("\x3A1","Rho")
  , ("\x1d54a","SS")
  , ("\x3A3","Sigma")
  , ("\x1d54b","TT")
  , ("\x3A4","Tau")
  , ("\x398","Theta")
  , ("\x1d54c","UU")
  , ("\x3A5","Upsilon")
  , ("\x1d54d","VV")
  , ("\x1d54e","WW")
  , ("\x1d54f","XX")
  , ("\x39E","Xi")
  , ("\x1d550","YY")
  , ("\x2124","ZZ")
  , ("\x396","Zeta")
  , ("\xb4","acute")
  , ("\x2dd","acute.double")
  , ("\x5d0","alef")
  , ("\x3b1","alpha")
  , ("&","amp")
  , ("\x214b","amp.inv")
  , ("\x2227","and")
  , ("\x22c0","and.big")
  , ("\x22cf","and.curly")
  , ("\x27d1","and.dot")
  , ("\x2a53","and.double")
  , ("\x2220","angle")
  , ("\x2329","angle.l")
  , ("\x232a","angle.r")
  , ("\x300a","angle.l.double")
  , ("\x300b","angle.r.double")
  , ("\x299f","angle.acute")
  , ("\x2221","angle.arc")
  , ("\x299b","angle.arc.rev")
  , ("\x29a3","angle.rev")
  , ("\x221f","angle.right")
  , ("\11262","angle.right.rev")
  , ("\x22be","angle.right.arc")
  , ("\x299d","angle.right.dot")
  , ("\x299c","angle.right.sq")
  , ("\x27c0","angle.spatial")
  , ("\x2222","angle.spheric")
  , ("\x29a0","angle.spheric.rev")
  , ("\x29a1","angle.spheric.top")
  , ("\x212B","angstrom")
  , ("\x2248","approx")
  , ("\x224a","approx.eq")
  , ("\x2249","approx.not")
  , ("\x2192","arrow.r")
  , ("\x27fc","arrow.r.long.bar")
  , ("\x21a6","arrow.r.bar")
  , ("\x2937","arrow.r.curve")
  , ("\x21e2","arrow.r.dashed")
  , ("\x2911","arrow.r.dotted")
  , ("\x21d2","arrow.r.double")
  , ("\x2907","arrow.r.double.bar")
  , ("\x27f9","arrow.r.double.long")
  , ("\x27fe","arrow.r.double.long.bar")
  , ("\x21cf","arrow.r.double.not")
  , ("\x27a1","arrow.r.filled")
  , ("\x21aa","arrow.r.hook")
  , ("\x27f6","arrow.r.long")
  , ("\x27ff","arrow.r.long.squiggly")
  , ("\x21ac","arrow.r.loop")
  , ("\x219b","arrow.r.not")
  , ("\x2b46","arrow.r.quad")
  , ("\x21dd","arrow.r.squiggly")
  , ("\x21e5","arrow.r.stop")
  , ("\x21e8","arrow.r.stroked")
  , ("\x21a3","arrow.r.tail")
  , ("\x21db","arrow.r.triple")
  , ("\x2905","arrow.r.twohead.bar")
  , ("\x21a0","arrow.r.twohead")
  , ("\x219d","arrow.r.wave")
  , ("\x2190","arrow.l")
  , ("\x21a4","arrow.l.bar")
  , ("\x2936","arrow.l.curve")
  , ("\x21e0","arrow.l.dashed")
  , ("\x2b38","arrow.l.dotted")
  , ("\x21d0","arrow.l.double")
  , ("\x2906","arrow.l.double.bar")
  , ("\x27f8","arrow.l.double.long")
  , ("\x27fd","arrow.l.double.long.bar")
  , ("\x21cd","arrow.l.double.not")
  , ("\x2b05","arrow.l.filled")
  , ("\x21a9","arrow.l.hook")
  , ("\x27f5","arrow.l.long")
  , ("\x27fb","arrow.l.long.bar")
  , ("\x2b33","arrow.l.long.squiggly")
  , ("\x21ab","arrow.l.loop")
  , ("\x219a","arrow.l.not")
  , ("\x2b45","arrow.l.quad")
  , ("\x21dc","arrow.l.squiggly")
  , ("\x21e4","arrow.l.stop")
  , ("\x21e6","arrow.l.stroked")
  , ("\x21a2","arrow.l.tail")
  , ("\x21da","arrow.l.triple")
  , ("\x2b36","arrow.l.twohead.bar")
  , ("\x219e","arrow.l.twohead")
  , ("\x219c","arrow.l.wave")
  , ("\x2191","arrow.t")
  , ("\x21a5","arrow.t.bar")
  , ("\x2934","arrow.t.curve")
  , ("\x21e1","arrow.t.dashed")
  , ("\x21d1","arrow.t.double")
  , ("\x2b06","arrow.t.filled")
  , ("\x27f0","arrow.t.quad")
  , ("\x2912","arrow.t.stop")
  , ("\x21e7","arrow.t.stroked")
  , ("\x290a","arrow.t.triple")
  , ("\x219f","arrow.t.twohead")
  , ("\x2193","arrow.b")
  , ("\x21a7","arrow.b.bar")
  , ("\x2935","arrow.b.curve")
  , ("\x21e3","arrow.b.dashed")
  , ("\x21d3","arrow.b.double")
  , ("\x2b07","arrow.b.filled")
  , ("\x27f1","arrow.b.quad")
  , ("\x2913","arrow.b.stop")
  , ("\x21e9","arrow.b.stroked")
  , ("\x290b","arrow.b.triple")
  , ("\x21a1","arrow.b.twohead")
  , ("\x2194","arrow.l.r")
  , ("\x21d4","arrow.l.r.double")
  , ("\x27fa","arrow.l.r.double.long")
  , ("\x21ce","arrow.l.r.double.not")
  , ("\x2b0c","arrow.l.r.filled")
  , ("\x27f7","arrow.l.r.long")
  , ("\x21ae","arrow.l.r.not")
  , ("\x2b04","arrow.l.r.stroked")
  , ("\x21ad","arrow.l.r.wave")
  , ("\x2195","arrow.t.b")
  , ("\x21d5","arrow.t.b.double")
  , ("\x2b0d","arrow.t.b.filled")
  , ("\x21f3","arrow.t.b.stroked")
  , ("\x2197","arrow.tr")
  , ("\x21d7","arrow.tr.double")
  , ("\x2b08","arrow.tr.filled")
  , ("\x2924","arrow.tr.hook")
  , ("\x2b00","arrow.tr.stroked")
  , ("\x2198","arrow.br")
  , ("\x21d8","arrow.br.double")
  , ("\x2b0a","arrow.br.filled")
  , ("\x2925","arrow.br.hook")
  , ("\x2b02","arrow.br.stroked")
  , ("\x2196","arrow.tl")
  , ("\x21d6","arrow.tl.double")
  , ("\x2b09","arrow.tl.filled")
  , ("\x2923","arrow.tl.hook")
  , ("\x2b01","arrow.tl.stroked")
  , ("\x2199","arrow.bl")
  , ("\x21d9","arrow.bl.double")
  , ("\x2b0b","arrow.bl.filled")
  , ("\x2926","arrow.bl.hook")
  , ("\x2b03","arrow.bl.stroked")
  , ("\x2921","arrow.tl.br")
  , ("\x2922","arrow.tr.bl")
  , ("\x21ba","arrow.ccw")
  , ("\x21b6","arrow.ccw.half")
  , ("\x21bb","arrow.cw")
  , ("\x21b7","arrow.cw.half")
  , ("\x21af","arrow.zigzag")
  , ("\x2303","arrowhead.t")
  , ("\x2304","arrowhead.b")
  , ("\x21c9","arrows.rr")
  , ("\x21c7","arrows.ll")
  , ("\x21c8","arrows.tt")
  , ("\x21ca","arrows.bb")
  , ("\x21c6","arrows.lr")
  , ("\x21b9","arrows.lr.stop")
  , ("\x21c4","arrows.rl")
  , ("\x21c5","arrows.tb")
  , ("\x21f5","arrows.bt")
  , ("\x21f6","arrows.rrr")
  , ("\x2b31","arrows.lll")
  , ("*","ast")
  , ("\x204e","ast.low")
  , ("\x2051","ast.double")
  , ("\x2042","ast.triple")
  , ("\xfe61","ast.small")
  , ("\x2217","ast.op")
  , ("\x229b","ast.circle")
  , ("\x29c6","ast.sq")
  , ("@","at")
  , ("\\","backslash")
  , ("\x29b8","backslash.circle")
  , ("\x29f7","backslash.not")
  , ("\x2610","ballot")
  , ("\x2612","ballot.x")
  , ("|","bar.v")
  , ("\x2016","bar.v.double")
  , ("\x2980","bar.v.triple")
  , ("\xa6","bar.v.broken")
  , ("\x29b6","bar.v.circle")
  , ("\x2015","bar.h")
  , ("\x2235","because")
  , ("\x5d1","bet")
  , ("\x3b2","beta")
  , ("\x3d0","beta.alt")
  , ("\x20bf","bitcoin")
  , ("\x22a5","bot")
  , ("{","brace.l")
  , ("}","brace.r")
  , ("\x23de","brace.t")
  , ("\x23df","brace.b")
  , ("[","bracket.l")
  , ("]","bracket.r")
  , ("\x23b4","bracket.t")
  , ("\x23b5","bracket.b")
  , ("\x2d8","breve")
  , ("\x2038","caret")
  , ("\x2c7","caron")
  , ("\x2713","checkmark")
  , ("\x1f5f8","checkmark.light")
  , ("\x3c7","chi")
  , ("\x25cb","circle.stroked")
  , ("\x2218","circle.stroked.tiny")
  , ("\x26ac","circle.stroked.small")
  , ("\x25ef","circle.stroked.big")
  , ("\x25cf","circle.filled")
  , ("\x2981","circle.filled.tiny")
  , ("\x2219","circle.filled.small")
  , ("\x2b24","circle.filled.big")
  , ("\x25cc","circle.dotted")
  , ("\x229a","circle.nested")
  , ("\x2105","co")
  , (":","colon")
  , ("\x2254","colon.eq")
  , ("\x2a74","colon.double.eq")
  , (",","comma")
  , ("\x2201","complement")
  , ("\x2218","compose")
  , ("\x2217","convolve")
  , ("\xa9","copyright")
  , ("\x2117","copyright.sound")
  , ("\x2020","dagger")
  , ("\x2021","dagger.double")
  , ("\x2013","dash.en")
  , ("\x2014","dash.em")
  , ("\x2012","dash.fig")
  , ("\x301c","dash.wave")
  , ("\x2239","dash.colon")
  , ("\x229d","dash.circle")
  , ("\x3030","dash.wave.double")
  , ("\xb0","degree")
  , ("\x2103","degree.c")
  , ("\x2109","degree.f")
  , ("\x3b4","delta")
  , ("\xa8","diaer")
  , ("\x2300","diameter")
  , ("\x25c7","diamond.stroked")
  , ("\x22c4","diamond.stroked.small")
  , ("\x2b26","diamond.stroked.medium")
  , ("\x27d0","diamond.stroked.dot")
  , ("\x25c6","diamond.filled")
  , ("\x2b25","diamond.filled.medium")
  , ("\x2b29","diamond.filled.small")
  , ("\x2202","diff")
  , ("\xf7","div")
  , ("\x2a38","div.circle")
  , ("\x2223","divides")
  , ("\x2224","divides.not")
  , ("$","dollar")
  , (".","dot")
  , ("\x22c5","dot.op")
  , ("\xb7","dot.c")
  , ("\x2299","dot.circle")
  , ("\x2a00","dot.circle.big")
  , ("\x22a1","dot.square")
  , ("\x2026","dots.h")
  , ("\x22ef","dots.h.c")
  , ("\x22ee","dots.v")
  , ("\x22f1","dots.down")
  , ("\x22f0","dots.up")
  , ("\x2113","ell")
  , ("\x2b2d","ellipse.stroked.h")
  , ("\x2b2f","ellipse.stroked.v")
  , ("\x2b2c","ellipse.filled.h")
  , ("\x2b2e","ellipse.filled.v")
  , ("\x3b5","epsilon")
  , ("\x3f5","epsilon.alt")
  , ("=","eq")
  , ("\x225b","eq.star")
  , ("\x229c","eq.circle")
  , ("\x2255","eq.colon")
  , ("\x225d","eq.def")
  , ("\x225c","eq.delta")
  , ("\x225a","eq.equi")
  , ("\x2259","eq.est")
  , ("\x22dd","eq.gt")
  , ("\x22dc","eq.lt")
  , ("\x225e","eq.m")
  , ("\x2260","eq.not")
  , ("\x22de","eq.prec")
  , ("\x225f","eq.quest")
  , ("\xfe66","eq.small")
  , ("\x22df","eq.succ")
  , ("\x3b7","eta")
  , ("\x20ac","euro")
  , ("!","excl")
  , ("\x203c","excl.double")
  , ("\xa1","excl.inv")
  , ("\x2049","excl.quest")
  , ("\x2203","exists")
  , ("\x2204","exists.not")
  , ("\x29d8","fence.l")
  , ("\x29da","fence.l.double")
  , ("\x29d9","fence.r")
  , ("\x29db","fence.r.double")
  , ("\x2999","fence.dotted")
  , ("\x2766","floral")
  , ("\x2619","floral.l")
  , ("\x2767","floral.r")
  , ("\x2200","forall")
  , ("\x20a3","franc")
  , ("\x3b3","gamma")
  , ("\x5d2","gimel")
  , ("`","grave")
  , (">","gt")
  , ("\x29c1","gt.circle")
  , ("\x22d7","gt.dot")
  , ("\x226b","gt.double")
  , ("\x2265","gt.eq")
  , ("\x22db","gt.eq.lt")
  , ("\x2271","gt.eq.not")
  , ("\x2267","gt.eqq")
  , ("\x2277","gt.lt")
  , ("\x2279","gt.lt.not")
  , ("\x2269","gt.neqq")
  , ("\x226f","gt.not")
  , ("\x22e7","gt.ntilde")
  , ("\xfe65","gt.small")
  , ("\x2273","gt.tilde")
  , ("\x2275","gt.tilde.not")
  , ("\x22d9","gt.triple")
  , ("\x2af8","gt.triple.nested")
  , ("\x21c0","harpoon.rt")
  , ("\x295b","harpoon.rt.bar")
  , ("\x2953","harpoon.rt.stop")
  , ("\x21c1","harpoon.rb")
  , ("\x295f","harpoon.rb.bar")
  , ("\x2957","harpoon.rb.stop")
  , ("\x21bc","harpoon.lt")
  , ("\x295a","harpoon.lt.bar")
  , ("\x2952","harpoon.lt.stop")
  , ("\x21bd","harpoon.lb")
  , ("\x295e","harpoon.lb.bar")
  , ("\x2956","harpoon.lb.stop")
  , ("\x21bf","harpoon.tl")
  , ("\x2960","harpoon.tl.bar")
  , ("\x2958","harpoon.tl.stop")
  , ("\x21be","harpoon.tr")
  , ("\x295c","harpoon.tr.bar")
  , ("\x2954","harpoon.tr.stop")
  , ("\x21c3","harpoon.bl")
  , ("\x2961","harpoon.bl.bar")
  , ("\x2959","harpoon.bl.stop")
  , ("\x21c2","harpoon.br")
  , ("\x295d","harpoon.br.bar")
  , ("\x2955","harpoon.br.stop")
  , ("\x294e","harpoon.lt.rt")
  , ("\x2950","harpoon.lb.rb")
  , ("\x294b","harpoon.lb.rt")
  , ("\x294a","harpoon.lt.rb")
  , ("\x2951","harpoon.tl.bl")
  , ("\x294f","harpoon.tr.br")
  , ("\x294d","harpoon.tl.br")
  , ("\x294c","harpoon.tr.bl")
  , ("\x2964","harpoons.rtrb")
  , ("\x2965","harpoons.blbr")
  , ("\x296f","harpoons.bltr")
  , ("\x2967","harpoons.lbrb")
  , ("\x2962","harpoons.ltlb")
  , ("\x21cb","harpoons.ltrb")
  , ("\x2966","harpoons.ltrt")
  , ("\x2969","harpoons.rblb")
  , ("\x21cc","harpoons.rtlb")
  , ("\x2968","harpoons.rtlt")
  , ("\x296e","harpoons.tlbr")
  , ("\x2963","harpoons.tltr")
  , ("#","hash")
  , ("^","hat")
  , ("\x2b21","hexa.stroked")
  , ("\x2b22","hexa.filled")
  , ("\x2010","hyph")
  , ("-","hyph.minus")
  , ("\x2011","hyph.nobreak")
  , ("\x2027","hyph.point")
  , ("\173","hyph.soft")
  , ("\x2261","ident")
  , ("\x2262","ident.not")
  , ("\x2263","ident.strict")
  , ("\x2208","in")
  , ("\x2209","in.not")
  , ("\x220b","in.rev")
  , ("\x220c","in.rev.not")
  , ("\x220d","in.rev.small")
  , ("\x220a","in.small")
  , ("\x221e","infinity")
  , ("\x222b","integral")
  , ("\x2a17","integral.arrow.hook")
  , ("\x2a11","integral.ccw")
  , ("\x222e","integral.cont")
  , ("\x2233","integral.cont.ccw")
  , ("\x2232","integral.cont.cw")
  , ("\x2231","integral.cw")
  , ("\x222c","integral.double")
  , ("\x2a0c","integral.quad")
  , ("\x2a19","integral.sect")
  , ("\x2a16","integral.sq")
  , ("\x222f","integral.surf")
  , ("\x2a18","integral.times")
  , ("\x222d","integral.triple")
  , ("\x2a1a","integral.union")
  , ("\x2230","integral.vol")
  , ("\x203d","interrobang")
  , ("\x3b9","iota")
  , ("\x2a1d","join")
  , ("\x27d6","join.r")
  , ("\x27d5","join.l")
  , ("\x27d7","join.l.r")
  , ("\x3d7","kai")
  , ("\x3ba","kappa")
  , ("\x3f0","kappa.alt")
  , ("\x212a","kelvin")
  , ("\x3bb","lambda")
  , ("\x20ba","lira")
  , ("\x25ca","lozenge.stroked")
  , ("\x2b2b","lozenge.stroked.small")
  , ("\x2b28","lozenge.stroked.medium")
  , ("\x29eb","lozenge.filled")
  , ("\x2b2a","lozenge.filled.small")
  , ("\x2b27","lozenge.filled.medium")
  , ("<","lt")
  , ("\x29c0","lt.circle")
  , ("\x22d6","lt.dot")
  , ("\x226a","lt.double")
  , ("\x2264","lt.eq")
  , ("\x22da","lt.eq.gt")
  , ("\x2270","lt.eq.not")
  , ("\x2266","lt.eqq")
  , ("\x2276","lt.gt")
  , ("\x2278","lt.gt.not")
  , ("\x2268","lt.neqq")
  , ("\x226e","lt.not")
  , ("\x22e6","lt.ntilde")
  , ("\xfe64","lt.small")
  , ("\x2272","lt.tilde")
  , ("\x2274","lt.tilde.not")
  , ("\x22d8","lt.triple")
  , ("\x2af7","lt.triple.nested")
  , ("\xaf","macron")
  , ("\x2720","maltese")
  , ("\x2212","minus")
  , ("\x2296","minus.circle")
  , ("\x2238","minus.dot")
  , ("\x2213","minus.plus")
  , ("\x229f","minus.square")
  , ("\x2242","minus.tilde")
  , ("\x2a3a","minus.triangle")
  , ("\x22a7","models")
  , ("\x3bc","mu")
  , ("\x22b8","multimap")
  , ("\x2207","nabla")
  , ("\xac","not")
  , ("\x1f39c","notes.up")
  , ("\x1f39d","notes.down")
  , ("\x2205","nothing")
  , ("\x29b0","nothing.rev")
  , ("\x3bd","nu")
  , ("\x2126","ohm")
  , ("\x2127","ohm.inv")
  , ("\x3c9","omega")
  , ("\x3bf","omicron")
  , ("\x221e","oo")
  , ("\x2228","or")
  , ("\x22c1","or.big")
  , ("\x22ce","or.curly")
  , ("\x27c7","or.dot")
  , ("\x2a54","or.double")
  , ("\x2225","parallel")
  , ("\x29b7","parallel.circle")
  , ("\x2226","parallel.not")
  , ("(","paren.l")
  , (")","paren.r")
  , ("\x23dc","paren.t")
  , ("\x23dd","paren.b")
  , ("\x2b20","penta.stroked")
  , ("\x2b1f","penta.filled")
  , ("%","percent")
  , ("\x2030","permille")
  , ("\x27c2","perp")
  , ("\x29b9","perp.circle")
  , ("\x20b1","peso")
  , ("\x3c6","phi")
  , ("\x3d5","phi.alt")
  , ("\x3c0","pi")
  , ("\x3d6","pi.alt")
  , ("\xb6","pilcrow")
  , ("\x204b","pilcrow.rev")
  , ("\x210e","planck")
  , ("\x210f","planck.reduce")
  , ("+","plus")
  , ("\x2295","plus.circle")
  , ("\x27f4","plus.circle.arrow")
  , ("\x2a01","plus.circle.big")
  , ("\x2214","plus.dot")
  , ("\xb1","plus.minus")
  , ("\xfe62","plus.small")
  , ("\x229e","plus.square")
  , ("\x2a39","plus.triangle")
  , ("\xa3","pound")
  , ("\x227a","prec")
  , ("\x2ab7","prec.approx")
  , ("\x2abb","prec.double")
  , ("\x227c","prec.eq")
  , ("\x22e0","prec.eq.not")
  , ("\x2ab3","prec.eqq")
  , ("\x2ab9","prec.napprox")
  , ("\x2ab5","prec.neqq")
  , ("\x2280","prec.not")
  , ("\x22e8","prec.ntilde")
  , ("\x227e","prec.tilde")
  , ("\x2032","prime")
  , ("\x2035","prime.rev")
  , ("\x2033","prime.double")
  , ("\x2036","prime.double.rev")
  , ("\x2034","prime.triple")
  , ("\x2037","prime.triple.rev")
  , ("\x2057","prime.quad")
  , ("\x220f","product")
  , ("\x2210","product.co")
  , ("\x221d","prop")
  , ("\x3c8","psi")
  , ("\x220e","qed")
  , ("?","quest")
  , ("\x2047","quest.double")
  , ("\x2048","quest.excl")
  , ("\xbf","quest.inv")
  , ("\"","quote.double")
  , ("'","quote.single")
  , ("\x201c","quote.l.double")
  , ("\x2018","quote.l.single")
  , ("\x201d","quote.r.double")
  , ("\x2019","quote.r.single")
  , ("\xab","quote.angle.l.double")
  , ("\x2039","quote.angle.l.single")
  , ("\xbb","quote.angle.r.double")
  , ("\x203a","quote.angle.r.single")
  , ("\x201f","quote.high.double")
  , ("\x201b","quote.high.single")
  , ("\x201e","quote.low.double")
  , ("\x201a","quote.low.single")
  , ("\x2236","ratio")
  , ("\x25ad","rect.stroked.h")
  , ("\x25af","rect.stroked.v")
  , ("\x25ac","rect.filled.h")
  , ("\x25ae","rect.filled.v")
  , ("\x203b","refmark")
  , ("\x3c1","rho")
  , ("\x3f1","rho.alt")
  , ("\x20bd","ruble")
  , ("\x20b9","rupee")
  , ("\x2229","sect")
  , ("\x2a44","sect.and")
  , ("\x22c2","sect.big")
  , ("\x2a40","sect.dot")
  , ("\x22d2","sect.double")
  , ("\x2293","sect.sq")
  , ("\x2a05","sect.sq.big")
  , ("\x2a4e","sect.sq.double")
  , ("\xa7","section")
  , (";","semi")
  , ("\x204f","semi.rev")
  , ("\x2120","servicemark")
  , ("\x5e9","shin")
  , ("\x3c3","sigma")
  , ("/","slash")
  , ("\x2afd","slash.double")
  , ("\x2afb","slash.triple")
  , ("\x2a33","smash")
  , ("s","space")
  , ("\xa0","space.nobreak")
  , ("\x2002","space.en")
  , ("\x2003","space.quad")
  , ("\x2004","space.third")
  , ("\x2005","space.quarter")
  , ("\x2006","space.sixth")
  , ("\x205f","space.med")
  , ("\x2007","space.fig")
  , ("\x2008","space.punct")
  , ("\x2009","space.thin")
  , ("\x200a","space.hair")
  , ("\x25a1","square.stroked")
  , ("\x25ab","square.stroked.tiny")
  , ("\x25fd","square.stroked.small")
  , ("\x25fb","square.stroked.medium")
  , ("\x2b1c","square.stroked.big")
  , ("\x2b1a","square.stroked.dotted")
  , ("\x25a2","square.stroked.rounded")
  , ("\x25a0","square.filled")
  , ("\x25aa","square.filled.tiny")
  , ("\x25fe","square.filled.small")
  , ("\x25fc","square.filled.medium")
  , ("\x2b1b","square.filled.big")
  , ("\x22c6","star.op")
  , ("\x2605","star.stroked")
  , ("\x2605","star.filled")
  , ("\x2282","subset")
  , ("\x2abd","subset.dot")
  , ("\x22d0","subset.double")
  , ("\x2286","subset.eq")
  , ("\x2288","subset.eq.not")
  , ("\x2291","subset.eq.sq")
  , ("\x22e2","subset.eq.sq.not")
  , ("\x228a","subset.neq")
  , ("\x2284","subset.not")
  , ("\x228f","subset.sq")
  , ("\x22e4","subset.sq.neq")
  , ("\x227b","succ")
  , ("\x2ab8","succ.approx")
  , ("\x2abc","succ.double")
  , ("\x227d","succ.eq")
  , ("\x22e1","succ.eq.not")
  , ("\x2ab4","succ.eqq")
  , ("\x2aba","succ.napprox")
  , ("\x2ab6","succ.neqq")
  , ("\x2281","succ.not")
  , ("\x22e9","succ.ntilde")
  , ("\x227f","succ.tilde")
  , ("\x2663","suit.club")
  , ("\x2666","suit.diamond")
  , ("\x2665","suit.heart")
  , ("\x2660","suit.spade")
  , ("\x2211","sum")
  , ("\x2a0b","sum.integral")
  , ("\x2283","supset")
  , ("\x2abe","supset.dot")
  , ("\x22d1","supset.double")
  , ("\x2287","supset.eq")
  , ("\x2289","supset.eq.not")
  , ("\x2292","supset.eq.sq")
  , ("\x22e3","supset.eq.sq.not")
  , ("\x228b","supset.neq")
  , ("\x2285","supset.not")
  , ("\x2290","supset.sq")
  , ("\x22e5","supset.sq.neq")
  , ("\x22a2","tack.r")
  , ("\x27dd","tack.r.long")
  , ("\x22a3","tack.l")
  , ("\x27de","tack.l.long")
  , ("\x2ade","tack.l.short")
  , ("\x22a5","tack.t")
  , ("\x27d8","tack.t.big")
  , ("\x2aeb","tack.t.double")
  , ("\x2ae0","tack.t.short")
  , ("\x22a4","tack.b")
  , ("\x27d9","tack.b.big")
  , ("\x2aea","tack.b.double")
  , ("\x2adf","tack.b.short")
  , ("\x27db","tack.l.r")
  , ("\x3c4","tau")
  , ("\x2234","therefore")
  , ("\x3b8","theta")
  , ("\x3d1","theta.alt")
  , ("~","tilde")
  , ("\x223c","tilde.op")
  , ("\x2243","tilde.eq")
  , ("\x2244","tilde.eq.not")
  , ("\x22cd","tilde.eq.rev")
  , ("\x2245","tilde.eqq")
  , ("\x2247","tilde.eqq.not")
  , ("\x2246","tilde.neqq")
  , ("\x2241","tilde.not")
  , ("\x223d","tilde.rev")
  , ("\x224c","tilde.rev.eqq")
  , ("\x224b","tilde.triple")
  , ("\xd7","times")
  , ("\x2a09","times.big")
  , ("\x2297","times.circle")
  , ("\x2a02","times.circle.big")
  , ("\x22c7","times.div")
  , ("\x22cb","times.l")
  , ("\x22cc","times.r")
  , ("\x22a0","times.square")
  , ("\x2a3b","times.triangle")
  , ("\x22a4","top")
  , ("\x25b7","triangle.stroked.r")
  , ("\x25c1","triangle.stroked.l")
  , ("\x25b3","triangle.stroked.t")
  , ("\x25bd","triangle.stroked.b")
  , ("\x25fa","triangle.stroked.bl")
  , ("\x25ff","triangle.stroked.br")
  , ("\x25f8","triangle.stroked.tl")
  , ("\x25f9","triangle.stroked.tr")
  , ("\x25b9","triangle.stroked.small.r")
  , ("\x25bf","triangle.stroked.small.b")
  , ("\x25c3","triangle.stroked.small.l")
  , ("\x25b5","triangle.stroked.small.t")
  , ("\x1f6c6","triangle.stroked.rounded")
  , ("\x27c1","triangle.stroked.nested")
  , ("\x25ec","triangle.stroked.dot")
  , ("\x25b6","triangle.filled.r")
  , ("\x25c0","triangle.filled.l")
  , ("\x25b2","triangle.filled.t")
  , ("\x25bc","triangle.filled.b")
  , ("\x25e3","triangle.filled.bl")
  , ("\x25e2","triangle.filled.br")
  , ("\x25e4","triangle.filled.tl")
  , ("\x25e5","triangle.filled.tr")
  , ("\x25b8","triangle.filled.small.r")
  , ("\x25be","triangle.filled.small.b")
  , ("\x25c2","triangle.filled.small.l")
  , ("\x25b4","triangle.filled.small.t")
  , ("\x3014","turtle.l")
  , ("\x3015","turtle.r")
  , ("\x23e0","turtle.t")
  , ("\x23e1","turtle.b")
  , ("\x222a","union")
  , ("\x228c","union.arrow")
  , ("\x22c3","union.big")
  , ("\x228d","union.dot")
  , ("\x2a03","union.dot.big")
  , ("\x22d3","union.double")
  , ("\x2a41","union.minus")
  , ("\x2a45","union.or")
  , ("\x228e","union.plus")
  , ("\x2a04","union.plus.big")
  , ("\x2294","union.sq")
  , ("\x2a06","union.sq.big")
  , ("\x2a4f","union.sq.double")
  , ("\x3c5","upsilon")
  , ("\x2216","without")
  , ("\8288","wj")
  , ("\x20a9","won")
  , ("\x2240","wreath")
  , ("\x3be","xi")
  , ("\xa5","yen")
  , ("\x3b6","zeta")
  , ("\x200d","zwj")
  , ("\x200c","zwnj")
  , ("\x200b","zws") ]
