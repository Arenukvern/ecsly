/// Priority constants for consistent ordering across the application.
///
/// Higher values indicate higher priority (handled first).
/// Use these constants instead of magic numbers for better maintainability.
library;

/// Background taps, default handlers
const int kPriorityBackground = 0;

/// Drawing and editing tools
const int kPriorityBrushTool = 400;

/// Camera controls (pan, zoom)
const int kPriorityCamera = 100;

/// Interactive handles and controls
const int kPriorityEmitterHandle = 500;

/// Game entities and interactive objects
const int kPriorityGameplay = 200;

/// Tooltips, dialogs, menus
const int kPriorityUI = 1000;
