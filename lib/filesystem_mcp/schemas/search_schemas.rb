# frozen_string_literal: true

module FileSystemMCP
  module Schemas
    module Search
      SEARCH_FILES = {
        type: "object",
        properties: {
          path: { type: "string", description: "Starting directory for search" },
          pattern: { type: "string", description: "Glob pattern (e.g., '*.txt', 'data/**/log?.log')" },
          excludePatterns: {
            type: "array",
            items: { type: "string" },
            default: [],
            description: "Glob patterns to exclude"
          }
        },
        required: ["path", "pattern"]
      }.freeze

      FIND_FILES = {
        type: "object",
        properties: {
          path: { type: "string", description: "Starting directory for search" },
          sort_by: { 
            type: "string", 
            enum: ["modified", "created", "size", "name"],
            description: "Sort results by specified criteria",
            default: "name"
          },
          order: {
            type: "string",
            enum: ["asc", "desc"],
            description: "Sort order (ascending or descending)",
            default: "asc"
          },
          limit: {
            type: "integer",
            minimum: 1,
            description: "Maximum number of results to return"
          },
          file_types: {
            type: "array",
            items: { type: "string" },
            description: "Filter by file extensions (e.g., ['txt', 'pdf', 'jpg'])"
          },
          modified_after: {
            type: "string",
            description: "Only include files modified after this ISO date (e.g., '2025-01-01T00:00:00Z')"
          },
          modified_before: {
            type: "string",
            description: "Only include files modified before this ISO date (e.g., '2025-12-31T23:59:59Z')"
          },
          min_size: {
            type: "integer",
            minimum: 0,
            description: "Minimum file size in bytes"
          },
          max_size: {
            type: "integer",
            minimum: 0,
            description: "Maximum file size in bytes"
          },
          include_directories: {
            type: "boolean",
            description: "Include directories in results",
            default: true
          }
        },
        required: ["path"]
      }.freeze
    end
  end
end