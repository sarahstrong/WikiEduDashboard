# frozen_string_literal: true

require_dependency "#{Rails.root}/lib/data_cycle/batch_update_logging"
require_dependency "#{Rails.root}/lib/importers/user_importer"
require_dependency "#{Rails.root}/lib/importers/assigned_article_importer"
require_dependency "#{Rails.root}/lib/articles_courses_cleaner"
require_dependency "#{Rails.root}/lib/importers/rating_importer"
require_dependency "#{Rails.root}/lib/article_status_manager"
require_dependency "#{Rails.root}/lib/importers/upload_importer"
require_dependency "#{Rails.root}/lib/importers/ores_scores_before_and_after_importer"
require_dependency "#{Rails.root}/lib/alerts/overdue_training_alert_manager"

# Executes all the steps of 'update_constantly' data import task
class DailyUpdate
  include BatchUpdateLogging

  def initialize
    setup_logger
    return if updates_paused?
    return if update_running?(:daily)

    run_update_with_pid_files(:daily)
  end

  private

  def run_update
    log_start_of_update 'Daily update tasks are beginning.'
    update_users
    update_commons_uploads
    update_article_data
    update_category_data
    generate_overdue_training_alerts if Features.wiki_ed?
    push_course_data_to_salesforce if Features.wiki_ed?
    log_end_of_update 'Daily update finished.'
  # rubocop:disable Lint/RescueException
  rescue Exception => e
    log_end_of_update 'Daily update failed.'
    raise e
  end
  # rubocop:enable Lint/RescueException

  ###############
  # Data import #
  ###############

  def update_users
    log_message 'Updating registration dates for new Users'
    UserImporter.update_users
  end

  def update_commons_uploads
    log_message 'Identifying deleted Commons uploads'
    UploadImporter.find_deleted_files
  end

  def update_article_data
    log_message 'Finding articles that match assignment titles'
    AssignedArticleImporter.import_articles_for_assignments

    log_message 'Rebuilding ArticlesCourses for all current students'
    ArticlesCoursesCleaner.rebuild_articles_courses

    log_message 'Updating ratings for all articles'
    RatingImporter.update_all_ratings

    log_message 'Updating article namespace and deleted status'
    ArticleStatusManager.update_article_status

    log_message 'Updating wp10 scores for before and after edits'
    OresScoresBeforeAndAfterImporter.import_all
  end

  def update_category_data
    log_message 'Updating tracked categories'
    Category.refresh_categories_for(Course.current)
  end

  ##########
  # Alerts #
  ##########
  def generate_overdue_training_alerts
    log_message 'Generating alerts for overdue trainings'
    OverdueTrainingAlertManager.new(Course.strictly_current).create_alerts
  end

  ###############
  # Data export #
  ###############
  def push_course_data_to_salesforce
    log_message 'Pushing course data to Salesforce'
    Course.current.each do |course|
      PushCourseToSalesforce.new(course) if course.flags[:salesforce_id]
    end
  end
end
