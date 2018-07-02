struct Clear::Migration::FullTextSearchableOperation < Clear::Migration::Operation
  module Priority
    VERY_IMPORTANT = 'A'
    IMPORTANT      = 'B'
    NORMAL         = 'C'
    LOW            = 'D'
  end

  getter table : String
  getter trigger_name : String
  getter function_name : String
  getter catalog : String
  getter dest_field : String

  getter multi_lang : String?
  getter src_fields : Array({String, Char})

  def initialize(@table, @src_fields, @catalog = "pg_catalog.english",
                 @multi_lang = nil, trigger_name = nil, function_name = nil,
                 @dest_field = "full_text_vector")
    raise "Source fields cannot be empty" if @src_fields.empty?

    @table = table

    @trigger_name = trigger_name || "tsv_update_#{table}"
    @function_name = function_name || "tsv_trigger_#{table}"
  end

  private def ensure_priority!(field_priority : Char)
    unless field_priority >= 'A' && field_priority <= 'D'
      raise "Priority level for tsvector range from 'A' (higher) to 'D' (lower)"
    end
  end

  private def print_concat_rules(use_new = true)
    src_fields.map do |(field_name, field_priority)|
      ensure_priority!(field_priority)

      "setweight(to_tsvector(#{Clear::Expression[catalog]}, coalesce(#{use_new && "new." || ""}#{field_name}, ''))," +
        " #{Clear::Expression[field_priority]})"
    end.join(" || ")
  end

  private def print_trigger : Array(String)
    op = if ml = @multi_lang
           raise "TODO"
         else
           "new.#{dest_field} := #{print_concat_rules};"
         end

    cr_fn = <<-SQL
      CREATE OR REPLACE FUNCTION #{function_name}() RETURNS trigger AS $$
      begin
        #{op}
        return new;
      end
      $$ LANGUAGE plpgsql;
    SQL

    cr_tr = <<-SQL
      CREATE TRIGGER #{trigger_name} BEFORE INSERT OR UPDATE
         ON #{table} FOR EACH ROW EXECUTE PROCEDURE #{function_name}();
      SQL

    return [cr_fn, cr_tr]
  end

  private def print_udpate_current_data
    op = if ml = @multi_lang
           raise "TODO"
         else
           print_concat_rules(use_new: false)
         end

    return [Clear::SQL.update(table)
      .set({"#{dest_field}" => Clear::Expression.unsafe(op)}).to_sql]
  end

  private def print_delete_trigger
    return ["DROP FUNCTION #{function_name}()", "DROP TRIGGER #{trigger_name}"]
  end

  def up
    print_trigger + print_udpate_current_data
  end

  def down
    print_delete_trigger
  end
end

module Clear::Migration::FullTextSearchableTableHelpers
  def full_text_searchable(on : Array(Tuple(String, Char)),
                           column_name = "full_text_vector", catalog = "pg_catalog.english",
                           multi_lang = nil, trigger_name = nil, function_name = nil)
    tsvector(column_name, index: "gin")

    migration.add_operation(Clear::Migration::FullTextSearchableOperation.new(self.name,
      on, catalog, multi_lang, trigger_name, function_name, column_name))
  end

  def full_text_searchable(on : String, column_name = "full_text_vector",
                           catalog = "pg_catalog.english",
                           multi_lang = nil, trigger_name = nil, function_name = nil)
    full_text_searchable([{on, 'C'}], column_name, catalog, multi_lang, trigger_name, function_name)
  end

  def full_text_searchable(on : Array(String), column_name = "full_text_vector",
                           catalog = "pg_catalog.english",
                           multi_lang = nil, trigger_name = nil, function_name = nil)
    raise "cannot implement tsv_searchable because empty array was given" if on.empty?

    fields = on.map { |name| {name, 'C'} }

    full_text_searchable(fields, column_name, catalog, multi_lang, trigger_name, function_name)
  end
end
