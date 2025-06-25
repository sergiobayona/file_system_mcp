# frozen_string_literal: true

module FileSystemMCP
  module Schemas
    module Info
      GET_FILE_INFO = {
        type: "object",
        properties: {
          path: { type: "string", description: "Path to get information about" }
        },
        required: ["path"]
      }.freeze

      GET_BULK_FILE_INFO = {
        type: "object",
        properties: {
          paths: {
            type: "array",
            items: { type: "string" },
            description: "Array of file/directory paths to get information about"
          },
          include_errors: {
            type: "boolean",
            description: "Include error information for inaccessible files",
            default: true
          }
        },
        required: ["paths"]
      }.freeze
    end
  end
end