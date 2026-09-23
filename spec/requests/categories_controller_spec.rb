# frozen_string_literal: true

RSpec.describe CategoriesController do
  fab!(:user)
  fab!(:category)

  before do
    SiteSetting.discourse_category_latest_topics_enabled = true
    SiteSetting.desktop_category_page_style = "categories_with_latest_topics"
    SiteSetting.mobile_category_page_style = "categories_only"
  end

  describe "#index" do
    it "serializes latest topic, author and read state independently of the featured-topic limit" do
      sign_in(user)
      category.update_column(:num_featured_topics, 0)
      poster = Fabricate(:user)
      topic =
        Fabricate(:topic, category: category, highest_post_number: 3, last_post_user_id: poster.id)
      TopicUser.change(
        user.id,
        topic.id,
        last_read_post_number: 1,
        notification_level: TopicUser.notification_levels[:tracking],
      )

      get "/categories.json"

      expect(response.status).to eq(200)
      row =
        response.parsed_body["category_list"]["categories"].find do |item|
          item["id"] == category.id
        end
      latest = row.fetch("category_latest_topics")
      expect(latest.map { |item| item["id"] }).to eq([topic.id])
      expect(latest.first["last_poster"]["username"]).to eq(poster.username)
      expect(latest.first["last_read_post_number"]).to eq(1)
      expect(latest.first["notification_level"]).to eq(TopicUser.notification_levels[:tracking])
    end

    it "preserves the native featured list when the other device uses it" do
      category.update!(num_featured_topics: 1)
      pinned = Fabricate(:topic, category: category, pinned_at: 1.day.ago)
      latest = Fabricate(:topic, category: category)
      CategoryFeaturedTopic.create!(category: category, topic: pinned)
      SiteSetting.mobile_category_page_style = "categories_with_featured_topics"

      get "/categories.json"

      expect(response.status).to eq(200)
      row =
        response.parsed_body["category_list"]["categories"].find do |item|
          item["id"] == category.id
        end
      expect(row.fetch("topics").map { |item| item["id"] }).to eq([pinned.id])
      expect(row.fetch("category_latest_topics").map { |item| item["id"] }).to eq([latest.id])
    end

    it "supports the mobile setting, child rows, and empty categories" do
      SiteSetting.desktop_category_page_style = "categories_only"
      SiteSetting.mobile_category_page_style = "categories_with_latest_topics"
      child = Fabricate(:category, parent_category: category)

      get "/categories.json", params: { include_subcategories: true }

      expect(response.status).to eq(200)
      row =
        response.parsed_body["category_list"]["categories"].find do |item|
          item["id"] == category.id
        end
      expect(row.fetch("category_latest_topics")).to eq([])
      expect(
        row["subcategory_list"]
          .find { |item| item["id"] == child.id }
          .fetch("category_latest_topics"),
      ).to eq([])
    end

    it "leaves native payloads unchanged when the plugin or new layout is disabled" do
      SiteSetting.discourse_category_latest_topics_enabled = false
      get "/categories.json"
      disabled_row =
        response.parsed_body["category_list"]["categories"].find do |item|
          item["id"] == category.id
        end
      expect(disabled_row).not_to have_key("category_latest_topics")

      SiteSetting.discourse_category_latest_topics_enabled = true
      SiteSetting.desktop_category_page_style = "categories_only"
      get "/categories.json"
      native_row =
        response.parsed_body["category_list"]["categories"].find do |item|
          item["id"] == category.id
        end
      expect(native_row).not_to have_key("category_latest_topics")
    end
  end
end
