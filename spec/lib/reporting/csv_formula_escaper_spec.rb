require 'rails_helper'
require 'reporting/csv_formula_escaper'

RSpec.describe Reporting::CsvFormulaEscaper do
  describe '.escape_cell' do
    it 'prefixes a single quote to strings that start with a formula trigger character' do
      aggregate_failures do
        [
          '=HYPERLINK("x")',
          '+1+cmd|"/C calc"!A0',
          '-2+3',
          '@SUM(A1:A2)',
          "\t=1+1",
          "\r=1+1",
        ].each do |value|
          expect(described_class.escape_cell(value)).to eq("'#{value}")
        end
      end
    end

    it 'leaves other values unchanged' do
      aggregate_failures do
        ['LA', 'a=b', '', ' =1', '-5', '+1.25', '-3.5%', 1, -1, 0.5, true, nil].each do |value|
          expect(described_class.escape_cell(value)).to eq(value)
        end
      end
    end
  end

  describe '.generate' do
    it 'escapes formula cells when generating a CSV' do
      csv = described_class.generate([['Header', 'Count'], ['=HYPERLINK("x")', 1]])

      expect(CSV.parse(csv)).to eq([['Header', 'Count'], ["'=HYPERLINK(\"x\")", '1']])
    end
  end
end
