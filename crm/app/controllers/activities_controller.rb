class ActivitiesController < ApplicationController
  before_action :require_login
  before_action :set_activity, only: [:show, :edit, :update, :destroy]

  def index
    @activities = Activity.includes(:activityable).order(due_at: :asc).page(params[:page]).per(20)
  end

  def show
  end

  def new
    @activity = Activity.new
    @activity.activityable_type = params[:activityable_type]
    @activity.activityable_id = params[:activityable_id]
  end

  def create
    @activity = Activity.new(activity_params)
    if @activity.save
      redirect_to polymorphic_path(@activity.activityable) || activities_path, notice: "Activity created."
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @activity.update(activity_params)
      redirect_to polymorphic_path(@activity.activityable) || activities_path, notice: "Activity updated."
    else
      render :edit
    end
  end

  def destroy
    parent = @activity.activityable
    @activity.destroy
    redirect_to parent ? polymorphic_path(parent) : activities_path, notice: "Activity deleted."
  end

  private

  def set_activity
    @activity = Activity.find(params[:id])
  end

  def activity_params
    params.require(:activity).permit(:activityable_type, :activityable_id, :activity_type, :subject, :description, :due_at, :status)
  end
end
