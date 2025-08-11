"""Create reviews table

Revision ID: 001
Revises: 
Create Date: 2024-01-01 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects.postgresql import UUID


# revision identifiers
revision = '001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade():
    """Create reviews table."""
    op.create_table(
        'reviews',
        sa.Column('id', UUID(as_uuid=True), primary_key=True),
        sa.Column('app_type', sa.String(100), nullable=False),
        sa.Column('store', sa.String(50), nullable=False),
        sa.Column('score', sa.Integer(), nullable=False),
        sa.Column('text', sa.Text(), nullable=False),
        sa.Column('date', sa.DateTime(), nullable=False),
        sa.Column('app_version', sa.String(50), nullable=False),
        sa.Column('likes_count', sa.Integer(), default=0),
        sa.Column('dislikes_count', sa.Integer(), default=0),
        sa.Column('device_manufacturer', sa.String(100), nullable=True),
        sa.Column('device_model', sa.String(100), nullable=True),
        sa.Column('device_firmware', sa.String(100), nullable=True),
        sa.Column('is_processed', sa.Boolean(), default=False),
        sa.Column('review_category', sa.String(50), nullable=True),
        sa.Column('store_review_id', sa.String(100), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=False),
        sa.Column('updated_at', sa.DateTime(), nullable=False),
    )
    
    # Создать уникальный индекс на store_review_id
    op.create_unique_constraint(
        'uq_reviews_store_review_id',
        'reviews',
        ['store_review_id']
    )
    
    # Создать индексы для оптимизации запросов
    op.create_index('idx_reviews_is_processed', 'reviews', ['is_processed'])
    op.create_index('idx_reviews_store_app_type', 'reviews', ['store', 'app_type'])
    op.create_index('idx_reviews_date', 'reviews', ['date'])


def downgrade():
    """Drop reviews table."""
    op.drop_table('reviews')