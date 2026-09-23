# frozen_string_literal: true

module ::DiscourseCategoryLatestTopics
  class LatestTopicsQuery
    def initialize(guardian:, category_ids:, tag: nil)
      @guardian = guardian
      @category_ids = category_ids.map(&:to_i).uniq
      @tag = tag
    end

    def call
      return Topic.none if @category_ids.empty?

      candidate_query = eligible_topics.where("topics.category_id = descendants.category_id")
      candidate_sql =
        candidate_query
          .reselect("topics.id, topics.bumped_at")
          .reorder(bumped_at: :desc, id: :desc)
          .limit(1)
          .to_sql

      selection_sql = <<~SQL
        WITH RECURSIVE descendants AS (
          SELECT categories.id AS root_category_id, categories.id AS category_id, 1 AS depth
          FROM categories
          WHERE categories.id IN (:category_ids)
          UNION ALL
          SELECT descendants.root_category_id, categories.id, descendants.depth + 1
          FROM categories
          JOIN descendants ON categories.parent_category_id = descendants.category_id
          WHERE descendants.depth < :max_depth
        )
        SELECT DISTINCT ON (descendants.root_category_id)
          descendants.root_category_id, candidate.id AS topic_id
        FROM descendants
        JOIN LATERAL (#{candidate_sql}) candidate ON true
        ORDER BY descendants.root_category_id, candidate.bumped_at DESC, candidate.id DESC
      SQL

      selection_sql =
        Topic.sanitize_sql_array(
          [
            selection_sql,
            { category_ids: @category_ids, max_depth: SiteSetting.max_category_nesting },
          ],
        )

      Topic
        .joins(
          "INNER JOIN (#{selection_sql}) category_latest ON category_latest.topic_id = topics.id",
        )
        .select("topics.*, category_latest.root_category_id AS category_latest_topic_category_id")
        .preload(
          :category,
          :shared_draft,
          :last_poster,
          { topic_thumbnails: %i[optimized_image upload] },
          *DiscoursePluginRegistry.category_list_topics_preloader_associations,
        )
    end

    private

    def eligible_topics
      options = { guardian: @guardian, limit: false, no_definitions: true, visible: true }
      options[:tags] = [@tag] if @tag.present?

      query =
        TopicQuery.new(@guardian.user, options).latest_results(
          skip_ordering: true,
          tags: options[:tags],
        )

      # Only IDs are needed inside the lateral query; preserve joins without eager-load columns.
      query.left_joins(*query.includes_values).except(:includes, :preload).where(pinned_at: nil)
    end
  end
end
