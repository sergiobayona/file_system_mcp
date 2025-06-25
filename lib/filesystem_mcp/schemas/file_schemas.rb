# frozen_string_literal: true

module FileSystemMCP
  module Schemas
    module File
      READ_FILE = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to the file to read" }
        },
        required: ["path"]
      }.freeze

      READ_MULTIPLE_FILES = {
        type: "object",
        properties: {
          paths: {
            type: "array",
            items: { type: "string" },
            description: "Array of file paths to read"
          }
        },
        required: ["paths"]
      }.freeze

      WRITE_FILE = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path where to write the file" },
          content: { type: "string", description: "Content to write to the file" }
        },
        required: ["path", "content"]
      }.freeze

      EDIT_FILE = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to the file to edit" },
          edits: {
            type: "array",
            items: {
              type: "object",
              properties: {
                oldText: { type: "string", description: "Text to search for - must match exactly" },
                newText: { type: "string", description: "Text to replace with" }
              },
              required: ["oldText", "newText"]
            },
            description: "Array of edit operations"
          },
          dryRun: { 
            type: "boolean", 
            description: "Preview changes using diff format", 
            default: false 
          }
        },
        required: ["path", "edits"]
      }.freeze

      MOVE_FILE = {
        type: "object",
        properties: {
          source: { type: "string", description: "Source path" },
          destination: { type: "string", description: "Destination path" }
        },
        required: ["source", "destination"]
      }.freeze
    end
  end
end