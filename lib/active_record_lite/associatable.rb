require 'active_support/core_ext/object/try'
require 'active_support/inflector'
require_relative './db_connection.rb'

class AssocParams
  attr_reader(
  :other_class_name, 
  :foreign_key,
  :primary_key
)
  
  def other_class
    @other_class_name.constantize
  end

  def other_table
    @other_class_name.table_name
  end
end

class BelongsToAssocParams < AssocParams
  def initialize(name, params)
    @foreign_key = params[:foreign_key] || "#{name}_id".to_sym
    @other_class_name = params[:class_name] || name.to_s.camelcase
    @primary_key = params[:primary_key] || :id
  end

  def type
    :belongs_to
  end
end

class HasManyAssocParams < AssocParams
  def initialize(name, params, self_class)
    @foreign_key = params[:foreign_key] || "#{self_class.name.underscore}_id".to_sym
    @other_class_name = params[:class_name] || (name.to_s.singularize.camelcase)
    @primary_key = params[:primary_key] || :id
  end

  def type
    :has_many
  end
end

module Associatable
  def assoc_params
    @assoc_params ||= {}
    @assoc_params
  end

  def belongs_to(name, params = {})
    belongs_association = BelongsToAssocParams.new(name, params)
    @assoc_params[name] = belongs_association
    
    define_method(name) do 
      results = DBConnection.execute(<<-SQL, self.send(belongs_association.foreign_key))
      SELECT *
      FROM #{belongs_association.other_table}
      WHERE #{belongs_association.other_table}.#{belongs_association.primary_key} = ?
      SQL
      
      belongs_association.other_class.parse_all(results).first
    end
  end
  
  As before, write a HasManyAssocParams class. You will need to calculate all the values as before. However, note a few differences:

  other_class_name should #singularize the association name before converting it to #camelcase.
  foreign_key should take the current class name, convert to snake_case with #underscore and add _id.
  For this reason, you should pass an extra argument (the current class), to HasManyAssocParams#initialize.
  
  def has_many(name, params = {})
    has_association = HasManyAssocParams.new(name, params, self)
    @assoc_params[name] = has_association
    
    define_method(name) do 
      
      # 
      results = DBConnection.execute(<<-SQL, self.send(has_association.primary_key))
        SELECT *
        FROM #{has_association.other_table}
        WHERE #{has_association.other_table}.#{has_association.foreign_key} = ?
      SQL
      
      has_association.other_table.parse_all(results)
    end
  end

  def has_one_through(name, assoc1, assoc2)
    # cat belongs to a human, foreign key is human_id, assoc1 foreign_key
    # human has a house, foreign key is human_id, assoc2 foreign_key
    # cat has a house through a human    
    
    define_method(name) do
      params1 = self.class.assoc_params[assoc1]
      params2 = params1.other_class.assoc_params[assoc2]
      pk1 = self.send(params1.foreign_key)
      results = DBConnection.execute(<<-SQL, pk1)
          SELECT #{params2.other_table}.*
          FROM #{params1.other_table}
          JOIN #{params2.other_table}
            ON #{params1.other_table}.#{params2.foreign_key}
                 = #{params2.other_table}.#{params2.primary_key}
         WHERE #{params1.other_table}.#{params1.primary_key}
                 = ?
      SQL

      params2.other_class.parse_all(results).first    
    end
  end
end
