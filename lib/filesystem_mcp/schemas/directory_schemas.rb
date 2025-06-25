# frozen_string_literal: true

module FileSystemMCP
  module Schemas
    module Directory
      LIST_DIRECTORY = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to the directory to list" },
          include_metadata: { 
            type: "boolean", 
            description: "Include file metadata (size, dates) in the response",
            default: false 
          }
        },
        required: ["path"]
      }.freeze

      CREATE_DIRECTORY = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path of the directory to create" }
        },
        required: ["path"]
      }.freeze
    end
  end
end