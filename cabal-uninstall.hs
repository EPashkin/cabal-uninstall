module Main where


import System.Environment (getArgs)
import System.Process (system, runInteractiveCommand)
import System.Exit (ExitCode(..))
import System.IO (hGetContents, hFlush, stdout)
import System.Directory (doesDirectoryExist, removeDirectoryRecursive)
import System.FilePath (takeDirectory, dropTrailingPathSeparator)
import Control.Monad.Instances ()


main :: IO ()
main = do
  input <- getArgs
  case input of
       package:args -> do
         let useForce = parseForceArg args
         res <- directoryOfPackage package
         case (res, useForce) of
              (Left err        , _         ) -> putStr err
              (_               , Nothing   ) -> putStrLn usageInfo
              (Right packageDir, Just force) -> do
                exitcode <- unregisterPackage package force
                case exitcode of
                     ExitFailure _ -> return ()
                     ExitSuccess -> do
                       b <- doesDirectoryExist packageDir
                       if b then removePackageDirectory packageDir
                            else putStrLn "package directory already deleted"
       _ -> putStrLn usageInfo

(<|) :: a -> [a] -> [a]
x <| xs = xs++[x]

usageInfo :: String
usageInfo =
  "version: 0.1.2\n\
  \usage: cabal-uninstall <package-name> [--force]\n\
  \use sudo if the package is installed globally"

internalErrorInfo :: String
internalErrorInfo =
  "internal error: please contact Jan Christiansen (j.christiansen@monoid-it.de)"

parseForceArg :: [String] -> Maybe Bool
parseForceArg []          = Just False
parseForceArg ["--force"] = Just True
parseForceArg _           = Nothing

directoryOfPackage :: String -> IO (Either String FilePath)
directoryOfPackage package = do
  let command = "ghc-pkg field " ++ package ++ " library-dirs"
  (_, hout, herr, _) <- runInteractiveCommand command
  result <- hGetContents hout
  case result of
       [] -> hGetContents herr >>= return . Left
       _  -> packageDir (words result)
 where
  packageDir libDirs =
    case extractLibDirs libDirs of
         Right [packDir] -> return (Right packDir)
         Right packDirs  -> multiPackageSelection packDirs
         Left  err       -> return (Left err)

multiPackageSelection :: [String] -> IO (Either String FilePath)
multiPackageSelection packagePaths = do
  putStr ("There are multiple packages with this name, please select one:\n"
          ++ unlines (zipWith line
                              [(1::Int)..]
                              (dontDelete <| packagePaths))
          ++ "\nPlease select a number\n")
  n <- getLine
  case reads n of
       [(i, "")] -> selectPackage i
       _         -> multiPackageSelection packagePaths
 where
  dontDelete = "don't delete any of these packages"
  line n packagePath = show n ++ ": " ++ packagePath
  selectPackage i
    | i == noOfPackages+1         = return (Left "No package selected\n")
    | i < 1 || i > noOfPackages+1 = multiPackageSelection packagePaths
    | otherwise                   = return (Right (packagePaths!!(i-1)))
  noOfPackages = length packagePaths

extractLibDirs :: [String] -> Either String [String]
extractLibDirs [] = Right []
extractLibDirs ("library-dirs:":libDir:libDirs) = do
    packDirs <- extractLibDirs libDirs
    return (takeDirectory (dropTrailingPathSeparator libDir):packDirs)
extractLibDirs _ = Left internalErrorInfo

removePackageDirectory :: FilePath -> IO ()
removePackageDirectory packageDir = do
  putStr ("delete library directory " ++ packageDir ++ "? (yes/no)")
  hFlush stdout
  choice <- getLine
  case choice of
       "yes" -> removeDirectoryRecursive packageDir
       _     -> return ()

unregisterPackage :: String -> Bool -> IO ExitCode
unregisterPackage package force = do
  putStrLn "unregistering package"
  system ("ghc-pkg unregister " ++ useForce force ++ package)
 where
  useForce True  = "--force "
  useForce False = ""
