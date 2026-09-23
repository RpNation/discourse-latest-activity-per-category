# frozen_string_literal: true
class AddCategoryLatestTopicsIndex < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  INDEX_NAME = "index_topics_on_category_latest_unpinned"

  def up
    remove_index :topics, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
    add_index :topics,
              %i[category_id bumped_at id],
              order: {
                bumped_at: :desc,
                id: :desc,
              },
              where:
                "deleted_at IS NULL AND archetype <> 'private_message' AND visible AND pinned_at IS NULL",
              name: INDEX_NAME,
              algorithm: :concurrently
  end

  def down
    remove_index :topics, name: INDEX_NAME, algorithm: :concurrently, if_exists: true
  end
end
