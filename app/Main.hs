{-# LANGUAGE OverloadedStrings #-}

module Main where

import qualified Data.Text as Text
import Data.Version (showVersion)
import qualified Paths_spacchetti_cli as Pcli
import qualified Turtle as T

-- | Commands that this program handles
data Command
  -- | Do the boilerplate of the local project setup to override and add arbitrary packages
  -- | See the Spacchetti docs about this here: https://spacchetti.readthedocs.io/en/latest/local-setup.html
  = LocalSetup Bool
  -- | Do the Ins-Dhall-ation of the local project setup, equivalent to:
  -- | ```sh
  -- | NAME='local'
  -- | TARGET=.psc-package/$NAME/.set/packages.json
  -- | mkdir -p .psc-package/$NAME/.set
  -- | dhall-to-json --pretty <<< './packages.dhall' > $TARGET
  -- | echo wrote packages.json to $TARGET
  -- | ```
  | InsDhall
  -- | Show spacchetti-cli version
  | Version

insDhall :: IO ()
insDhall = do
  T.mktree (T.fromText basePath)
  T.touch (T.fromText packagesJson)
  code <- T.shell ("cat ./packages.dhall | dhall-to-json --pretty > " <> packagesJson) T.empty

  case code of
    T.ExitSuccess ->
      T.echo $ T.unsafeTextToLine ("wrote packages.json to " <> packagesJson)
    T.ExitFailure n ->
      T.die ("failed to insdhall: " <> T.repr n)

  where
    basePath = ".psc-package/local/.set/"
    packagesJson = basePath <> "packages.json"

unsafePathToText :: T.FilePath -> T.Text
unsafePathToText p = case T.toText p of
  Left t -> t
  Right t -> t

checkFiles :: [T.FilePath] -> IO ()
checkFiles = T.void . traverse checkFile
  where
    checkFile p = do
      hasFile <- T.testfile p
      T.when hasFile $
        T.die $ "Found " <> unsafePathToText p <> ": there's already a project here. "
             <> "Run `spacchetti local-setup --force` if you're sure you want to overwrite it."

localSetup :: Bool -> IO ()
localSetup force = do
  T.unless force $
    checkFiles [ pscPackageJsonPath, packagesDhallPath ]

  T.touch pscPackageJsonPath
  T.touch packagesDhallPath

  T.writeTextFile pscPackageJsonPath pscPackageJsonTemplate
  T.writeTextFile packagesDhallPath packagesDhallTemplate

  _ <- T.shell ("dhall format --inplace " <> packagesDhallText) T.empty

  T.echo "Set up local Spacchetti packages."

  where
    packagesDhallText = "packages.dhall"
    pscPackageJsonPath = T.fromText "psc-package.json"
    packagesDhallPath = T.fromText packagesDhallText

    pscPackageJsonTemplate = "{\"name\": \"my-project\", \"set\": \"local\", \"source\": \"\", \"depends\": []}"
    packagesDhallTemplate = "let mkPackage = https://raw.githubusercontent.com/justinwoo/spacchetti/140918/src/mkPackage.dhall in let upstream = https://raw.githubusercontent.com/justinwoo/spacchetti/140918/src/packages.dhall in upstream"

printVersion :: IO ()
printVersion =
  T.echo $ T.unsafeTextToLine (Text.pack $ showVersion Pcli.version)

parser :: T.Parser Command
parser
      = LocalSetup <$> localSetup
  T.<|> InsDhall <$ insDhall
  T.<|> Version <$ version
  where
    localSetup =
      T.subcommand
      "local-setup" "run project-local Spacchetti setup" $
      T.switch "force" 'f' "Overwrite any project found in the current directory."
    insDhall = T.subcommand "insdhall" "insdhall the local package set" $ pure ()
    version = T.subcommand "version" "Show spacchetti-cli version" $ pure ()

main :: IO ()
main = do
  command <- T.options "Spacchetti CLI" parser
  case command of
    LocalSetup force -> localSetup force
    InsDhall         -> insDhall
    Version          -> printVersion
