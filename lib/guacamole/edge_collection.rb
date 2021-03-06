# -*- encoding : utf-8 -*-

require 'guacamole/collection'
require 'guacamole/graph_query'

require 'ashikawa-core'
require 'active_support'
require 'active_support/concern'
require 'active_support/core_ext/string/inflections'

module Guacamole
  module EdgeCollection
    extend ActiveSupport::Concern
    include Guacamole::Collection

    class << self
      def for(edge_class)
        collection_name = [edge_class.name.pluralize, 'Collection'].join

        collection_name.constantize
      rescue NameError
        create_edge_collection(collection_name)
      end

      def create_edge_collection(collection_name)
        new_collection_class = Class.new
        Object.const_set(collection_name, new_collection_class)
        new_collection_class.send(:include, Guacamole::EdgeCollection)
      end
    end

    module ClassMethods
      def connection
        @connection ||= graph.edge_collection(collection_name)
      end

      def edge_class
        @edge_class ||= model_class
      end

      def add_edge_definition_to_graph
        graph.add_edge_definition(collection_name,
                                  from: [edge_class.from],
                                  to: [edge_class.to])
      rescue Ashikawa::Core::ResourceNotFound
        # FIXME: We just assume this 404 is raised because the edge definition is already created.
        #        But the source of the error could be something else too. Had to be changed as soon
        #        https://github.com/triAGENS/ashikawa-core/issues/136 is done.
      end

      def neighbors(model, direction = :inbound)
        aql_string = <<-AQL
        FOR n IN GRAPH_NEIGHBORS(@graph,
                        { _key: @model_key },
                        { direction: @direction, edgeCollectionRestriction: @edge_collection })
          RETURN n.vertex
        AQL

        bind_parameters = {
          graph: Guacamole.configuration.graph.name,
          model_key: model.key,
          edge_collection: collection_name,
          direction: direction
        }

        options = { return_as: nil, for_in: nil }

        query                 = AqlQuery.new(self, mapper_for_target(model), options)
        query.aql_fragment    = aql_string
        query.bind_parameters = bind_parameters
        query
      end

      def mapper_for_target(model)
        vertex_mapper.find { |mapper| !mapper.responsible_for?(model) }
      end

      def mapper_for_start(model)
        vertex_mapper.find { |mapper| mapper.responsible_for?(model) }
      end

      def vertex_mapper
        [edge_class.from_collection, edge_class.to_collection].map(&:mapper)
      end
    end

    included do
      add_edge_definition_to_graph
    end
  end
end
