
module SPARQL; class Client
  ##
  # A SPARQL query builder.
  #
  # @example Iterating over all found solutions
  #   query.each_solution { |solution| puts solution.inspect }
  #
  class Query < RDF::Query
    ##
    # @return [Symbol]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#QueryForms
    attr_reader :form

    ##
    # @return [Hash{Symbol => Object}]
    attr_reader :options

    ##
    # Creates a boolean `ASK` query.
    #
    # @param  [Hash{Symbol => Object}] options
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#ask
    def self.ask(options = {})
      self.new(:ask, options)
    end

    ##
    # Creates a tuple `SELECT` query.
    #
    # @param  [Array<Symbol>]          variables
    # @param  [Hash{Symbol => Object}] options
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#select
    def self.select(*variables)
      options = variables.last.is_a?(Hash) ? variables.pop : {}
      self.new(:select, options).select(*variables) # FIXME
    end

    ##
    # Creates a graph `CONSTRUCT` query.
    #
    # @param  [Array<RDF::Query::Pattern, Array>] patterns
    # @param  [Hash{Symbol => Object}]            options
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#construct
    def self.construct(*patterns)
      options = patterns.last.is_a?(Hash) ? patterns.pop : {}
      self.new(:construct, options).construct(*patterns) # FIXME
    end

    ##
    # @param  [Symbol, #to_s]          form
    # @param  [Hash{Symbol => Object}] options
    # @yield  [query]
    # @yieldparam [Query]
    def initialize(form = :ask, options = {}, &block)
      @form = form.respond_to?(:to_sym) ? form.to_sym : form.to_s.to_sym
      super(options.dup, &block)
    end

    ##
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#ask
    def ask
      @form = :ask
      self
    end

    ##
    # @param  [Array<Symbol>] variables
    # @param  [Hash{Symbol => Object}] options
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#select
    def select(*variables)
      @form = :select
      options = variables.last.is_a?(Hash) ? variables.pop : {}
      @variables = variables.inject({}) do |vars, var|
        vars.merge(var.to_sym => RDF::Query::Variable.new(var))
      end
      self
    end

    ##
    # @param  [Array<RDF::Query::Pattern, Array>] patterns
    # @return [Query]
    def construct(*patterns)
      options[:template] = patterns.map do |pattern|
        case pattern
          when RDF::Query::Pattern then pattern
          else RDF::Query::Pattern.new(*pattern.to_a)
        end
      end
      self
    end

    ##
    # @param  [Array<RDF::Query::Pattern, Array>] patterns
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#GraphPattern
    def where(*patterns)
      @patterns += patterns.map do |pattern|
        case pattern
          when RDF::Query::Pattern then pattern
          else RDF::Query::Pattern.new(*pattern.to_a)
        end
      end
      self
    end

    alias_method :whether, :where

    ##
    # @param  [Array<Symbol>] variables
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#modOrderBy
    def order(*variables)
      options[:order_by] = variables
      self
    end

    alias_method :order_by, :order

    ##
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#modDistinct
    def distinct(state = true)
      options[:distinct] = state
      self
    end

    ##
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#modReduced
    def reduced(state = true)
      options[:reduced] = state
      self
    end

    ##
    # @param  [Integer, #to_i] start
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#modOffset
    def offset(start)
      slice(start, nil)
    end

    ##
    # @param  [Integer, #to_i] length
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#modResultLimit
    def limit(length)
      slice(nil, length)
    end

    ##
    # @param  [Integer, #to_i] start
    # @param  [Integer, #to_i] length
    # @return [Query]
    def slice(start, length)
      options[:offset] = start.to_i if start
      options[:limit] = length.to_i if length
      self
    end

    ##
    # @return [Query]
    # @see    http://www.w3.org/TR/rdf-sparql-query/#prefNames
    def prefix(string)
      (options[:prefixes] ||= []) << string
      self
    end

    ##
    # @private
    def filter(string)
      (options[:filters] ||= []) << string
      self
    end

    ##
    # @return [Boolean]
    def true?
      case result
        when TrueClass, FalseClass then result
        when Enumerable then !result.empty?
        else false
      end
    end

    ##
    # @return [Boolean]
    def false?
      !true?
    end

    ##
    # @return [Enumerable<RDF::Query::Solution>]
    def solutions
      result
    end

    ##
    # @yield  [statement]
    # @yieldparam [RDF::Statement]
    # @return [Enumerator]
    def each_statement(&block)
      result.each_statement(&block)
    end

    ##
    # @return [Object]
    def result
      @result ||= execute
    end

    ##
    # @return [Object]
    def execute
      raise NotImplementedError
    end

    ##
    # Returns the string representation of this query.
    #
    # @return [String]
    def to_s
      buffer = [form.to_s.upcase]
      case form
        when :select
          buffer << 'DISTINCT' if options[:distinct]
          buffer << 'REDUCED'  if options[:reduced]
          buffer << (variables.empty? ? '*' : variables.values.map { |v| serialize_value(v) }.join(' '))
        when :construct
          buffer << '{'
          buffer += options[:template].map do |p|
            p.to_triple.map { |v| serialize_value(v) }.join(' ') + " ."
          end
          buffer << '}'
      end

      buffer << 'WHERE {'
      buffer += patterns.map do |p|
        p.to_triple.map { |v| serialize_value(v) }.join(' ') + " ."
      end
      if options[:filters]
        buffer += options[:filters].map { |filter| "FILTER(#{filter})" }
      end
      buffer << '}'

      if options[:order_by]
        buffer << 'ORDER BY'
        buffer += options[:order_by].map { |var| "?#{var}" }
      end

      buffer << "OFFSET #{options[:offset]}" if options[:offset]
      buffer << "LIMIT #{options[:limit]}"   if options[:limit]
      options[:prefixes].reverse.each {|e| buffer.unshift("PREFIX #{e}") } if options[:prefixes]

      buffer.join(' ')
    end

    ##
    # Outputs a developer-friendly representation of this query to `stderr`.
    #
    # @return [void]
    def inspect!
      warn(inspect)
      self
    end

    ##
    # Returns a developer-friendly representation of this query.
    #
    # @return [String]
    def inspect
      sprintf("#<%s:%#0x(%s)>", self.class.name, __id__, to_s)
    end

    ##
    # Serializes an RDF::Value into a format appropriate for select, construct, and where clauses
    #
    # @param  [RDF::Value]
    # @return [String]
    # @private
    def serialize_value(value)
      # SPARQL queries are UTF-8, but support ASCII-style Unicode escapes, so
      # the N-Triples serializer is fine unless it's a variable:
      case
        when value.variable? then "?#{value.name}"
        else RDF::NTriples.serialize(value)
      end
    end
  end
end; end
