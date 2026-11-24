// DictusCore/Sources/DictusCore/Logger.swift
import os.log

/// Centralized loggers for Dictus subsystems.
/// Usage: DictusLogger.keyboard.debug("message")
@available(iOS 14.0, macOS 11.0, *)
public enum DictusLogger {
    public static let app = Logger(subsystem: "dev.starkharness.riff2", category: "app")
    public static let keyboard = Logger(subsystem: "dev.starkharness.riff2", category: "keyboard")
    public static let appGroup = Logger(subsystem: "dev.starkharness.riff2", category: "appGroup")
}
