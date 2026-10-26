# frozen_string_literal: true

require 'csv'

module Reporting
  # Neutralizes spreadsheet formula injection ("CSV injection") by prefixing a single quote
  # to string cells that a spreadsheet program would otherwise evaluate as a formula.
  module CsvFormulaEscaper
    FORMULA_TRIGGER_CHARACTERS = ['=', '+', '-', '@', "\t", "\r"].freeze
    PLAIN_NUMBER = /\A[+-]?\d+(\.\d+)?%?\z/

    module_function

    # @param [Object] value
    # @return [Object] the value, with a leading "'" if it is a String that starts with a formula
    #   trigger character
    def escape_cell(value)
      return value unless value.is_a?(String)
      return value unless value.start_with?(*FORMULA_TRIGGER_CHARACTERS)
      return value if value.match?(PLAIN_NUMBER)

      "'#{value}"
    end

    # @param [Array] row
    # @return [Array]
    def escape_row(row)
      row.map { |value| escape_cell(value) }
    end

    # @param [Array<Array>] rows
    # @return [String]
    def generate(rows)
      CSV.generate do |csv|
        rows.each do |row|
          csv << escape_row(row)
        end
      end
    end
  end
end
