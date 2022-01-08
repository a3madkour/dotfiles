-- Base

-- Actions

-- Data

-- Hooks

-- for some fullscreen events, also for xcomposite in obs.

-- Layouts

-- Layouts modifiers

-- Utilities

import qualified DBus.Client as DC
import Data.Char
  ( isSpace,
    toUpper,
  )
import qualified Data.Map as M
import Data.Maybe
  ( fromJust,
    isJust,
  )
import Data.Monoid
import Data.Tree
import System.Directory
import System.Exit (exitSuccess)
import System.IO (hPutStrLn)
import XMonad
import XMonad.Actions.CopyWindow (kill1)
import XMonad.Actions.CycleWS
  ( Direction1D (..),
    WSType (..),
    moveTo,
    nextScreen,
    nextWS,
    prevScreen,
    prevWS,
    shiftTo,
  )
import XMonad.Actions.GridSelect
import XMonad.Actions.MouseResize
import XMonad.Actions.Promote
import XMonad.Actions.RotSlaves
  ( rotAllDown,
    rotSlavesDown,
  )
import qualified XMonad.Actions.Search as S
import XMonad.Actions.UpdatePointer
import XMonad.Actions.WindowGo (runOrRaise)
import XMonad.Actions.WithAll
  ( killAll,
    sinkAll,
  )
import qualified XMonad.DBus as D
import XMonad.Hooks.DynamicLog
  ( PP (..),
    dynamicLogWithPP,
    shorten,
    wrap,
    xmobarColor,
    xmobarPP,
  )
import XMonad.Hooks.EwmhDesktops
import XMonad.Hooks.ManageDocks
  ( ToggleStruts (..),
    avoidStruts,
    docksEventHook,
    manageDocks,
  )
import XMonad.Hooks.ManageHelpers
  ( doCenterFloat,
    doFullFloat,
    isFullscreen,
  )
import XMonad.Hooks.ServerMode
import XMonad.Hooks.SetWMName
import XMonad.Hooks.WorkspaceHistory
import XMonad.Layout.Accordion
import XMonad.Layout.GridVariants (Grid (Grid))
import XMonad.Layout.LayoutModifier
import XMonad.Layout.LimitWindows
  ( decreaseLimit,
    increaseLimit,
    limitWindows,
  )
import XMonad.Layout.Magnifier
import XMonad.Layout.MultiToggle
  ( EOT (EOT),
    mkToggle,
    single,
    (??),
  )
import qualified XMonad.Layout.MultiToggle as MT
  ( Toggle (..),
  )
import XMonad.Layout.MultiToggle.Instances
  ( StdTransformers
      ( MIRROR,
        NBFULL,
        NOBORDERS
      ),
  )
import XMonad.Layout.NoBorders
import XMonad.Layout.Renamed
import XMonad.Layout.ResizableTile
import XMonad.Layout.ShowWName
import XMonad.Layout.Simplest
import XMonad.Layout.SimplestFloat
import XMonad.Layout.Spacing
import XMonad.Layout.Spiral
import XMonad.Layout.SubLayouts
import XMonad.Layout.Tabbed
import XMonad.Layout.ThreeColumns
import qualified XMonad.Layout.ToggleLayouts as T
  ( ToggleLayout (Toggle),
    toggleLayouts,
  )
import XMonad.Layout.WindowArranger
  ( WindowArrangerMsg (..),
    windowArrange,
  )
import XMonad.Layout.WindowNavigation
import qualified XMonad.StackSet as W
import XMonad.Util.Dmenu
import XMonad.Util.EZConfig (additionalKeysP)
import XMonad.Util.NamedScratchpad
import XMonad.Util.Run
  ( runProcessWithInput,
    safeSpawn,
    spawnPipe,
  )
import XMonad.Util.SpawnOnce

myFont :: String
myFont =
  "xft:SauceCodePro Nerd Font Mono:regular:size=9:antialias=true:hinting=true"

--Makes setting the spacingRaw simpler to write. The spacingRaw module adds a configurable amount of space around windows.
mySpacing ::
  Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing i = spacingRaw False (Border i i i i) True (Border i i i i) True

-- Below is a variation of the above except no borders are applied
-- if fewer than two windows. So a single window has no gaps.
mySpacing' ::
  Integer -> l a -> XMonad.Layout.LayoutModifier.ModifiedLayout Spacing l a
mySpacing' i = spacingRaw True (Border i i i i) True (Border i i i i) True

-- Defining a bunch of layouts, many that I don't use.
-- limitWindows n sets maximum number of windows displayed for layout.
-- mySpacing n sets the gap size around the windows.
tall =
  renamed [Replace "tall"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 12 $
              mySpacing 0 $
                ResizableTall 1 (3 / 100) (1 / 2) []

myMagnify =
  renamed [Replace "magnify"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            magnifier $
              limitWindows 12 $
                mySpacing 0 $
                  ResizableTall 1 (3 / 100) (1 / 2) []

monocle =
  renamed [Replace "monocle"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 20 Full

floats =
  renamed [Replace "floats"] $ smartBorders $ limitWindows 20 simplestFloat

grid =
  renamed [Replace "grid"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 12 $
              mySpacing 0 $
                mkToggle (single MIRROR) $
                  Grid (16 / 10)

spirals =
  renamed [Replace "spirals"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            mySpacing' 0 $
              spiral (6 / 7)

threeCol =
  renamed [Replace "threeCol"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 7 $
              ThreeCol 1 (3 / 100) (1 / 2)

threeRow =
  renamed [Replace "threeRow"] $
    smartBorders $
      windowNavigation $
        addTabs shrinkText myTabTheme $
          subLayout [] (smartBorders Simplest) $
            limitWindows 7
            -- Mirror takes a layout and rotates it by 90 degrees.
            -- So we are applying Mirror to the ThreeCol layout.
            $
              Mirror $
                ThreeCol 1 (3 / 100) (1 / 2)

tabs =
  renamed [Replace "tabs"]
  -- I cannot add spacing to this layout because it will
  -- add spacing between window and tabs which looks bad.
  $
    tabbed shrinkText myTabTheme

tallAccordion = renamed [Replace "tallAccordion"] $ Accordion

wideAccordion = renamed [Replace "wideAccordion"] $ Mirror Accordion

myEmacs :: String
myEmacs = "emacsclient -c -a 'emacs' " -- Makes emacs keybindings easier to type

myEditor :: String
myEditor = "emacs" -- Sets emacs as myeditor

myBrowser :: String
myBrowser = "brave" -- Sets qutebrowser as mybrowser

myTerminal = "alacritty" -- Sets default terminal

myBorderWidth :: Dimension
myBorderWidth = 2 -- Sets border width for windows

myNormColor :: String
myNormColor = "#282c34" -- Border color of normal windows

myFocusColor :: String
myFocusColor = "#46d9ff" -- Border color of focused windows

windowCount :: X (Maybe String)
windowCount =
  gets $
    Just
      . show
      . length
      . W.integrate'
      . W.stack
      . W.workspace
      . W.current
      . windowset

myStartupHook :: X ()
myStartupHook = do
  spawnOnce "lxsession &"
  spawnOnce "picom &"
  spawnOnce "nm-applet &"
  spawnOnce "setxkbmap -option caps:escape"
  spawnOnce "davmail"
  spawnOnce "xsetroot -cursor_name left_ptr"
  spawnOnce "autorandr --change"
  spawnOnce "conky -c $HOME/.config/conky/doomone-xmonad.conkyrc"
  -- spawnOnce "trayer --edge top --align right --widthtype request --padding 6 --SetDockType true --SetPartialStrut true --expand true --monitor 1 --transparent true --alpha 0 --tint 0x282c34  --height 22 &"
  spawnOnce "/usr/bin/emacs --daemon &"
  -- spawnOnce "~/.config/polybar/launch.sh"
  spawnOnce "feh --randomize --bg-fill ~/Sync/Wallpapers/*"
  setWMName "LG3D"

myManageHook :: XMonad.Query (Data.Monoid.Endo WindowSet)
myManageHook =
  composeAll
    [ className =? "confirm" --> doFloat,
      className =? "file_progress" --> doFloat,
      className =? "download" --> doFloat,
      className =? "error" --> doFloat,
      className =? "Gimp" --> doFloat,
      className =? "notification" --> doFloat,
      className =? "pinentry-gtk-2" --> doFloat,
      className =? "splash" --> doFloat,
      className =? "toolbar" --> doFloat,
      isFullscreen --> doFullFloat,
      manageDocks
    ]

myKeys :: [(String, X ())]
myKeys =
  [ ("M-C-r", spawn "xmonad --recompile"),
    -- Recompiles xmonad
    ("M-M1-r", spawn "xmonad --restart"),
    -- Restarts xmonad
    ("M-S-q", io exitSuccess),
    -- Quits xmonad
    ("M-S-/", spawn "~/.xmonad/xmonad_keys.sh"),
    ("M-S-<Return>", spawn "dmenu_run -i -p \"Run: \""),
    -- Dmenu

    -- KB_GROUP Useful programs to have a keybinding for launch
    ("M-<Return>", spawn (myTerminal)),
    -- , ("M-a", spawn "emacsclient -nc -a=''")
    ("M-a", spawn myEmacs),
    ("M-c", spawn myEditor),
    ("M-b", spawn myBrowser),
    ("M-s", spawn "mpg123 ~/Sync/donotquestionmyallegiancecomrade.mp3"),
    -- Important
    ("M-x", spawn "pkill mpg123"),
    -- Equally Important
    ("M-z", spawn "passdmenu"),
    -- Passwods

    -- KB_GROUP Kill windows
    ("M-S-c", kill1),
    -- Kill the currently focused client
    ("M-S-a", killAll),
    -- Kill all windows on current workspace

    -- KB_GROUP Workspaces
    ("M-<Left>", prevWS),
    -- Switch to next workspace
    ("M-<Right>", nextWS),
    -- Switch to next workspace
    ("M-.", nextScreen),
    -- Switch focus to next monitor
    ("M-,", prevScreen),
    -- Switch focus to prev monitor
    ("M-S-<KP_Add>", shiftTo Next nonNSP >> moveTo Next nonNSP),
    -- Shifts focused window to next ws
    ("M-S-<KP_Subtract>", shiftTo Prev nonNSP >> moveTo Prev nonNSP),
    -- Shifts focused window to prev ws

    -- KB_GROUP Windows navigation
    ("M-m", windows W.focusMaster),
    -- Move focus to the master window
    ("M-j", windows W.focusDown),
    -- Move focus to the next window
    ("M-k", windows W.focusUp),
    -- Move focus to the prev window
    ("M-S-m", windows W.swapMaster),
    -- Swap the focused window and the master window
    ("M-S-j", windows W.swapDown),
    -- Swap focused window with next window
    ("M-S-k", windows W.swapUp),
    -- Swap focused window with prev window
    ("M-<Backspace>", promote),
    -- Moves focused window to master, others maintain order
    ("M-S-<Tab>", rotSlavesDown),
    -- Rotate all windows except master and keep focus in place
    ("M-C-<Tab>", rotAllDown),
    -- Rotate all the windows in the current stack

    -- KB_GROUP Layouts
    ("M-<Tab>", sendMessage NextLayout),
    -- Switch to next layout
    ("M-<Space>", sendMessage (MT.Toggle NBFULL) >> sendMessage ToggleStruts),
    -- Toggles noborder/full

    -- KB_GROUP Increase/decrease windows in the master pane or the stack
    ("M-S-<Up>", sendMessage (IncMasterN 1)),
    -- Increase # of clients master pane
    ("M-S-<Down>", sendMessage (IncMasterN (-1))),
    -- Decrease # of clients master pane
    ("M-C-<Up>", increaseLimit),
    -- Increase # of windows
    ("M-C-<Down>", decreaseLimit),
    -- Decrease # of windows

    -- KB_GROUP Window resizing
    ("M-h", sendMessage Shrink),
    -- Shrink horiz window width
    ("M-l", sendMessage Expand),
    -- Expand horiz window width
    ("M-M1-j", sendMessage MirrorShrink),
    -- Shrink vert window width
    ("M-M1-k", sendMessage MirrorExpand),
    -- Expand vert window width

    -- KB_GROUP Sublayouts
    -- This is used to push windows to tabbed sublayouts, or pull them out of it.
    ("M-C-h", sendMessage $ pullGroup L),
    ("M-C-l", sendMessage $ pullGroup R),
    ("M-C-k", sendMessage $ pullGroup U),
    ("M-C-j", sendMessage $ pullGroup D),
    ("M-C-m", withFocused (sendMessage . MergeAll)),
    -- , ("M-C-u", withFocused (sendMessage . UnMerge))
    ("M-C-/", withFocused (sendMessage . UnMergeAll)),
    ("M-C-.", onGroup W.focusUp'),
    -- Switch focus to next tab
    ("M-C-,", onGroup W.focusDown'),
    -- Switch focus to prev tab
    ("M-<F1>", spawn "sxiv -r -q -t -o /home/a3madkour/Sync/Wallpapers/*"),
    ( "M-<F2>",
      spawn
        "find /home/a3madkour/Sync/Wallpapers// -type f | shuf -n 1 | xargs xwallpaper --stretch"
    ),
    -- KB_GROUP Controls for mocp music player (SUPER-u followed by a key)
    ("M-u p", spawn "mocp --play"),
    ("M-u l", spawn "mocp --next"),
    ("M-u h", spawn "mocp --previous"),
    ("M-u <Space>", spawn "mocp --toggle-pause"),
    -- KB_GROUP Multimedia Keys
    ("<XF86AudioPlay>", spawn "mocp --play"),
    ("<XF86AudioPrev>", spawn "mocp --previous"),
    ("<XF86AudioNext>", spawn "mocp --next"),
    ("<XF86AudioMute>", spawn "amixer set Master toggle"),
    ("<XF86AudioLowerVolume>", spawn "amixer set Master 5%- unmute"),
    ("<XF86AudioRaiseVolume>", spawn "amixer set Master 5%+ unmute"),
    ("<XF86MonBrightnessUp>", spawn "brightnessctl s +10%"),
    ("<XF86MonBrightnessDown>", spawn "brightnessctl s 10%-"),
    ("<XF86Search>", spawn "dm-websearch"),
    ("<XF86Mail>", runOrRaise "thunderbird" (resource =? "thunderbird")),
    ( "<XF86Calculator>",
      runOrRaise "qalculate-gtk" (resource =? "qalculate-gtk")
    ),
    ("<XF86Eject>", spawn "toggleeject"),
    ("<Print>", spawn "dm-maim")
  ]
  where
    -- The following lines are needed for named scratchpads.
    nonNSP = WSIs (return (\ws -> W.tag ws /= "NSP"))
    nonEmptyNonNSP =
      WSIs (return (\ws -> isJust (W.stack ws) && W.tag ws /= "NSP"))

-- END_KEYS

myWorkspaces = [" 1 ", " 2 ", " 3 ", " 4 ", " 5 ", " 6 ", " 7 ", " 8 ", " 9 "]

-- myLogHook :: DC.Client -> PP
-- myLogHook dbus = def { ppOutput = D.send dbus }

myBar = "polybar"

polybarHook :: DC.Client -> PP
polybarHook dbus =
  let wrapper c s
        | s /= "NSP" = wrap ("%{F" <> c <> "} ") " %{F-}" s
        | otherwise = mempty
      blue = "#2E9AFE"
      gray = "#7F7F7F"
      orange = "#ea4300"
      purple = "#9058c7"
      red = "#722222"
   in def
        { ppOutput = D.send dbus,
          ppCurrent = wrapper blue,
          ppVisible = wrapper gray,
          ppUrgent = wrapper orange,
          ppHidden = wrapper gray,
          ppHiddenNoWindows = wrapper red,
          ppTitle = wrapper purple . shorten 90
        }

myWorkspaceIndices = M.fromList $ zipWith (,) myWorkspaces [1 ..] -- (,) == \x y -> (x,y)

-- setting colors for tabs layout and tabs sublayout.
myTabTheme =
  def
    { fontName = myFont,
      activeColor = "#46d9ff",
      inactiveColor = "#313846",
      activeBorderColor = "#46d9ff",
      inactiveBorderColor = "#282c34",
      activeTextColor = "#282c34",
      inactiveTextColor = "#d0d0d0"
    }

myLayoutHook =
  avoidStruts $
    mouseResize $
      windowArrange $
        T.toggleLayouts floats $
          mkToggle
            (NBFULL ?? NOBORDERS ?? EOT)
            myDefaultLayout
  where
    myDefaultLayout =
      withBorder myBorderWidth tall
        ||| myMagnify
        ||| noBorders monocle
        ||| floats
        ||| noBorders tabs
        ||| grid
        ||| spirals
        ||| threeCol
        ||| threeRow
        ||| tallAccordion
        ||| wideAccordion

clickable ws =
  "<action=xdotool key super+" ++ show i ++ ">" ++ ws ++ "</action>"
  where
    i = fromJust $ M.lookup ws myWorkspaceIndices

myConfig =
  def
    { modMask = mod4Mask,
      terminal = myTerminal,
      layoutHook = myLayoutHook,
      manageHook = myManageHook,
      startupHook = myStartupHook,
      workspaces = myWorkspaces
    }
    `additionalKeysP` myKeys

main :: IO ()
main = do
  dbus <- D.connect
  D.requestAccess dbus
  xmonad $ myConfig {logHook = dynamicLogWithPP (polybarHook dbus)}
