export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5"
  }
  public: {
    Tables: {
      age_groups: {
        Row: {
          created_at: string
          id: string
          max_age: number | null
          min_age: number | null
          name: string
          sort_order: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          max_age?: number | null
          min_age?: number | null
          name: string
          sort_order?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          max_age?: number | null
          min_age?: number | null
          name?: string
          sort_order?: number
          updated_at?: string
        }
        Relationships: []
      }
      audit_logs: {
        Row: {
          action: string
          actor_id: string | null
          after_state: Json | null
          before_state: Json | null
          correlation_id: string | null
          created_at: string
          entity_id: string | null
          entity_type: string
          id: string
          ip_address: unknown
          reason: string | null
          user_agent: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          correlation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type: string
          id?: string
          ip_address?: unknown
          reason?: string | null
          user_agent?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_state?: Json | null
          before_state?: Json | null
          correlation_id?: string | null
          created_at?: string
          entity_id?: string | null
          entity_type?: string
          id?: string
          ip_address?: unknown
          reason?: string | null
          user_agent?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "audit_logs_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      canteen_categories: {
        Row: {
          created_at: string
          display_order: number
          id: string
          is_active: boolean
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          display_order?: number
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
        }
        Relationships: []
      }
      canteen_order_items: {
        Row: {
          allergen_snapshot: string[]
          created_at: string
          id: string
          line_total_cents: number
          options_snapshot: Json
          order_id: string
          product_id: string | null
          product_name_snapshot: string
          quantity: number
          unit_price_cents_snapshot: number
        }
        Insert: {
          allergen_snapshot?: string[]
          created_at?: string
          id?: string
          line_total_cents: number
          options_snapshot?: Json
          order_id: string
          product_id?: string | null
          product_name_snapshot: string
          quantity: number
          unit_price_cents_snapshot: number
        }
        Update: {
          allergen_snapshot?: string[]
          created_at?: string
          id?: string
          line_total_cents?: number
          options_snapshot?: Json
          order_id?: string
          product_id?: string | null
          product_name_snapshot?: string
          quantity?: number
          unit_price_cents_snapshot?: number
        }
        Relationships: [
          {
            foreignKeyName: "canteen_order_items_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "canteen_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "canteen_order_items_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "canteen_products"
            referencedColumns: ["id"]
          },
        ]
      }
      canteen_orders: {
        Row: {
          created_at: string
          customer_id: string
          discount_cents: number
          id: string
          idempotency_key: string | null
          order_number: string
          order_status: string
          payment_status: string
          pickup_window_end: string | null
          pickup_window_start: string | null
          qr_token_hash: string | null
          recipient_id: string | null
          special_instructions: string | null
          subtotal_cents: number
          total_cents: number
          updated_at: string
          venue_id: string | null
        }
        Insert: {
          created_at?: string
          customer_id: string
          discount_cents?: number
          id?: string
          idempotency_key?: string | null
          order_number: string
          order_status?: string
          payment_status?: string
          pickup_window_end?: string | null
          pickup_window_start?: string | null
          qr_token_hash?: string | null
          recipient_id?: string | null
          special_instructions?: string | null
          subtotal_cents?: number
          total_cents?: number
          updated_at?: string
          venue_id?: string | null
        }
        Update: {
          created_at?: string
          customer_id?: string
          discount_cents?: number
          id?: string
          idempotency_key?: string | null
          order_number?: string
          order_status?: string
          payment_status?: string
          pickup_window_end?: string | null
          pickup_window_start?: string | null
          qr_token_hash?: string | null
          recipient_id?: string | null
          special_instructions?: string | null
          subtotal_cents?: number
          total_cents?: number
          updated_at?: string
          venue_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "canteen_orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "canteen_orders_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "canteen_orders_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "canteen_venues"
            referencedColumns: ["id"]
          },
        ]
      }
      canteen_products: {
        Row: {
          allergen_info: string[]
          category_id: string | null
          created_at: string
          description: string | null
          dietary_info: string[]
          display_order: number
          gst_cents: number
          id: string
          image_url: string | null
          is_active: boolean
          is_sold_out: boolean
          max_quantity_per_order: number | null
          name: string
          preparation_minutes: number
          price_cents: number
          updated_at: string
        }
        Insert: {
          allergen_info?: string[]
          category_id?: string | null
          created_at?: string
          description?: string | null
          dietary_info?: string[]
          display_order?: number
          gst_cents?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_sold_out?: boolean
          max_quantity_per_order?: number | null
          name: string
          preparation_minutes?: number
          price_cents: number
          updated_at?: string
        }
        Update: {
          allergen_info?: string[]
          category_id?: string | null
          created_at?: string
          description?: string | null
          dietary_info?: string[]
          display_order?: number
          gst_cents?: number
          id?: string
          image_url?: string | null
          is_active?: boolean
          is_sold_out?: boolean
          max_quantity_per_order?: number | null
          name?: string
          preparation_minutes?: number
          price_cents?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "canteen_products_category_id_fkey"
            columns: ["category_id"]
            isOneToOne: false
            referencedRelation: "canteen_categories"
            referencedColumns: ["id"]
          },
        ]
      }
      canteen_venues: {
        Row: {
          created_at: string
          id: string
          is_active: boolean
          name: string
          updated_at: string
          venue_id: string | null
        }
        Insert: {
          created_at?: string
          id?: string
          is_active?: boolean
          name: string
          updated_at?: string
          venue_id?: string | null
        }
        Update: {
          created_at?: string
          id?: string
          is_active?: boolean
          name?: string
          updated_at?: string
          venue_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "canteen_venues_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      club_announcements: {
        Row: {
          audience: string
          created_at: string
          created_by: string | null
          ends_at: string | null
          id: string
          message: string
          priority: number
          starts_at: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          audience?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string | null
          id?: string
          message: string
          priority?: number
          starts_at?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          audience?: string
          created_at?: string
          created_by?: string | null
          ends_at?: string | null
          id?: string
          message?: string
          priority?: number
          starts_at?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_announcements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      club_events: {
        Row: {
          capacity: number | null
          created_at: string
          description: string | null
          ends_at: string | null
          id: string
          image_url: string | null
          price_cents: number
          registration_closes_at: string | null
          registration_opens_at: string | null
          slug: string
          starts_at: string
          status: string
          title: string
          updated_at: string
          venue_id: string | null
          visibility: string
        }
        Insert: {
          capacity?: number | null
          created_at?: string
          description?: string | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          price_cents?: number
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          slug: string
          starts_at: string
          status?: string
          title: string
          updated_at?: string
          venue_id?: string | null
          visibility?: string
        }
        Update: {
          capacity?: number | null
          created_at?: string
          description?: string | null
          ends_at?: string | null
          id?: string
          image_url?: string | null
          price_cents?: number
          registration_closes_at?: string | null
          registration_opens_at?: string | null
          slug?: string
          starts_at?: string
          status?: string
          title?: string
          updated_at?: string
          venue_id?: string | null
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "club_events_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      coaching_resources: {
        Row: {
          age_group_tags: string[]
          body: Json
          created_at: string
          created_by: string | null
          duration_minutes: number | null
          equipment_required: string[]
          id: string
          resource_type: string
          skill_level_tags: string[]
          status: string
          summary: string | null
          title: string
          updated_at: string
          visibility: string
        }
        Insert: {
          age_group_tags?: string[]
          body?: Json
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          equipment_required?: string[]
          id?: string
          resource_type: string
          skill_level_tags?: string[]
          status?: string
          summary?: string | null
          title: string
          updated_at?: string
          visibility?: string
        }
        Update: {
          age_group_tags?: string[]
          body?: Json
          created_at?: string
          created_by?: string | null
          duration_minutes?: number | null
          equipment_required?: string[]
          id?: string
          resource_type?: string
          skill_level_tags?: string[]
          status?: string
          summary?: string | null
          title?: string
          updated_at?: string
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "coaching_resources_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      communication_outbox: {
        Row: {
          channel: string
          created_at: string
          failure_reason: string | null
          id: string
          payload: Json
          recipient_id: string | null
          related_entity_id: string | null
          related_entity_type: string | null
          scheduled_for: string
          sent_at: string | null
          status: string
          template_key: string | null
        }
        Insert: {
          channel: string
          created_at?: string
          failure_reason?: string | null
          id?: string
          payload?: Json
          recipient_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          scheduled_for?: string
          sent_at?: string | null
          status?: string
          template_key?: string | null
        }
        Update: {
          channel?: string
          created_at?: string
          failure_reason?: string | null
          id?: string
          payload?: Json
          recipient_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          scheduled_for?: string
          sent_at?: string | null
          status?: string
          template_key?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "communication_outbox_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      competitions: {
        Row: {
          created_at: string
          external_url: string | null
          id: string
          name: string
          season_id: string | null
          updated_at: string
        }
        Insert: {
          created_at?: string
          external_url?: string | null
          id?: string
          name: string
          season_id?: string | null
          updated_at?: string
        }
        Update: {
          created_at?: string
          external_url?: string | null
          id?: string
          name?: string
          season_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "competitions_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
        ]
      }
      content_articles: {
        Row: {
          author_id: string | null
          body: Json
          category: string | null
          created_at: string
          featured_image_url: string | null
          id: string
          publish_at: string | null
          seo_description: string | null
          seo_title: string | null
          slug: string
          summary: string | null
          tags: string[]
          title: string
          updated_at: string
          workflow_status: string
        }
        Insert: {
          author_id?: string | null
          body?: Json
          category?: string | null
          created_at?: string
          featured_image_url?: string | null
          id?: string
          publish_at?: string | null
          seo_description?: string | null
          seo_title?: string | null
          slug: string
          summary?: string | null
          tags?: string[]
          title: string
          updated_at?: string
          workflow_status?: string
        }
        Update: {
          author_id?: string | null
          body?: Json
          category?: string | null
          created_at?: string
          featured_image_url?: string | null
          id?: string
          publish_at?: string | null
          seo_description?: string | null
          seo_title?: string | null
          slug?: string
          summary?: string | null
          tags?: string[]
          title?: string
          updated_at?: string
          workflow_status?: string
        }
        Relationships: [
          {
            foreignKeyName: "content_articles_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      event_registrations: {
        Row: {
          answers: Json
          attendee_id: string | null
          checked_in_at: string | null
          checked_in_by: string | null
          created_at: string
          event_id: string
          id: string
          registered_by: string | null
          status: string
          updated_at: string
        }
        Insert: {
          answers?: Json
          attendee_id?: string | null
          checked_in_at?: string | null
          checked_in_by?: string | null
          created_at?: string
          event_id: string
          id?: string
          registered_by?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          answers?: Json
          attendee_id?: string | null
          checked_in_at?: string | null
          checked_in_by?: string | null
          created_at?: string
          event_id?: string
          id?: string
          registered_by?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "event_registrations_attendee_id_fkey"
            columns: ["attendee_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_checked_in_by_fkey"
            columns: ["checked_in_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_event_id_fkey"
            columns: ["event_id"]
            isOneToOne: false
            referencedRelation: "club_events"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "event_registrations_registered_by_fkey"
            columns: ["registered_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      families: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          name: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          name: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          name?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "families_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      family_members: {
        Row: {
          accepted_at: string | null
          can_manage: boolean
          can_spend: boolean
          created_at: string
          family_id: string
          id: string
          invited_by: string | null
          is_primary_guardian: boolean
          relationship: string
          spending_limit_cents: number | null
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          accepted_at?: string | null
          can_manage?: boolean
          can_spend?: boolean
          created_at?: string
          family_id: string
          id?: string
          invited_by?: string | null
          is_primary_guardian?: boolean
          relationship: string
          spending_limit_cents?: number | null
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          accepted_at?: string | null
          can_manage?: boolean
          can_spend?: boolean
          created_at?: string
          family_id?: string
          id?: string
          invited_by?: string | null
          is_primary_guardian?: boolean
          relationship?: string
          spending_limit_cents?: number | null
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "family_members_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_members_invited_by_fkey"
            columns: ["invited_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "family_members_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      file_records: {
        Row: {
          bucket: string
          created_at: string
          id: string
          mime_type: string | null
          object_path: string
          owner_id: string | null
          related_entity_id: string | null
          related_entity_type: string | null
          size_bytes: number | null
          visibility: string
        }
        Insert: {
          bucket: string
          created_at?: string
          id?: string
          mime_type?: string | null
          object_path: string
          owner_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          size_bytes?: number | null
          visibility?: string
        }
        Update: {
          bucket?: string
          created_at?: string
          id?: string
          mime_type?: string | null
          object_path?: string
          owner_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          size_bytes?: number | null
          visibility?: string
        }
        Relationships: [
          {
            foreignKeyName: "file_records_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      fixtures: {
        Row: {
          competition_id: string | null
          created_at: string
          external_url: string | null
          home_away: string | null
          id: string
          opponent: string
          round: string | null
          season_id: string
          starts_at: string
          status: string
          team_id: string
          updated_at: string
          venue_id: string | null
        }
        Insert: {
          competition_id?: string | null
          created_at?: string
          external_url?: string | null
          home_away?: string | null
          id?: string
          opponent: string
          round?: string | null
          season_id: string
          starts_at: string
          status?: string
          team_id: string
          updated_at?: string
          venue_id?: string | null
        }
        Update: {
          competition_id?: string | null
          created_at?: string
          external_url?: string | null
          home_away?: string | null
          id?: string
          opponent?: string
          round?: string | null
          season_id?: string
          starts_at?: string
          status?: string
          team_id?: string
          updated_at?: string
          venue_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "fixtures_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixtures_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixtures_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "fixtures_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      inventory_movements: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          movement_type: string
          product_id: string
          quantity: number
          reason: string | null
          related_entity_id: string | null
          related_entity_type: string | null
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          movement_type: string
          product_id: string
          quantity: number
          reason?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          movement_type?: string
          product_id?: string
          quantity?: number
          reason?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "inventory_movements_created_by_fkey"
            columns: ["created_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "inventory_movements_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "canteen_products"
            referencedColumns: ["id"]
          },
        ]
      }
      match_reports: {
        Row: {
          author_id: string
          conduct_issues: string | null
          created_at: string
          final_score_against: number | null
          final_score_for: number | null
          fixture_id: string | null
          highlights: string | null
          id: string
          improvement_notes: string | null
          injury_notes: string | null
          private_notes: string | null
          result: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          reviewer_notes: string | null
          status: string
          team_id: string
          updated_at: string
        }
        Insert: {
          author_id: string
          conduct_issues?: string | null
          created_at?: string
          final_score_against?: number | null
          final_score_for?: number | null
          fixture_id?: string | null
          highlights?: string | null
          id?: string
          improvement_notes?: string | null
          injury_notes?: string | null
          private_notes?: string | null
          result?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewer_notes?: string | null
          status?: string
          team_id: string
          updated_at?: string
        }
        Update: {
          author_id?: string
          conduct_issues?: string | null
          created_at?: string
          final_score_against?: number | null
          final_score_for?: number | null
          fixture_id?: string | null
          highlights?: string | null
          id?: string
          improvement_notes?: string | null
          injury_notes?: string | null
          private_notes?: string | null
          result?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          reviewer_notes?: string | null
          status?: string
          team_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "match_reports_author_id_fkey"
            columns: ["author_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_reports_fixture_id_fkey"
            columns: ["fixture_id"]
            isOneToOne: false
            referencedRelation: "fixtures"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_reports_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "match_reports_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      merchandise_orders: {
        Row: {
          created_at: string
          customer_id: string
          id: string
          notes: string | null
          order_number: string
          pickup_or_delivery: string
          status: string
          total_cents: number
          updated_at: string
        }
        Insert: {
          created_at?: string
          customer_id: string
          id?: string
          notes?: string | null
          order_number: string
          pickup_or_delivery?: string
          status?: string
          total_cents?: number
          updated_at?: string
        }
        Update: {
          created_at?: string
          customer_id?: string
          id?: string
          notes?: string | null
          order_number?: string
          pickup_or_delivery?: string
          status?: string
          total_cents?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "merchandise_orders_customer_id_fkey"
            columns: ["customer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      merchandise_products: {
        Row: {
          category: string | null
          created_at: string
          description: string | null
          featured: boolean
          id: string
          image_url: string | null
          name: string
          status: string
          updated_at: string
        }
        Insert: {
          category?: string | null
          created_at?: string
          description?: string | null
          featured?: boolean
          id?: string
          image_url?: string | null
          name: string
          status?: string
          updated_at?: string
        }
        Update: {
          category?: string | null
          created_at?: string
          description?: string | null
          featured?: boolean
          id?: string
          image_url?: string | null
          name?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      merchandise_variants: {
        Row: {
          colour: string | null
          created_at: string
          id: string
          is_active: boolean
          low_stock_threshold: number
          price_cents: number
          product_id: string
          sale_price_cents: number | null
          size: string | null
          sku: string | null
          stock_quantity: number
          updated_at: string
        }
        Insert: {
          colour?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          low_stock_threshold?: number
          price_cents: number
          product_id: string
          sale_price_cents?: number | null
          size?: string | null
          sku?: string | null
          stock_quantity?: number
          updated_at?: string
        }
        Update: {
          colour?: string | null
          created_at?: string
          id?: string
          is_active?: boolean
          low_stock_threshold?: number
          price_cents?: number
          product_id?: string
          sale_price_cents?: number | null
          size?: string | null
          sku?: string | null
          stock_quantity?: number
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "merchandise_variants_product_id_fkey"
            columns: ["product_id"]
            isOneToOne: false
            referencedRelation: "merchandise_products"
            referencedColumns: ["id"]
          },
        ]
      }
      notifications: {
        Row: {
          body: string
          created_at: string
          id: string
          read_at: string | null
          recipient_id: string
          related_entity_id: string | null
          related_entity_type: string | null
          title: string
        }
        Insert: {
          body: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id: string
          related_entity_id?: string | null
          related_entity_type?: string | null
          title: string
        }
        Update: {
          body?: string
          created_at?: string
          id?: string
          read_at?: string | null
          recipient_id?: string
          related_entity_id?: string | null
          related_entity_type?: string | null
          title?: string
        }
        Relationships: [
          {
            foreignKeyName: "notifications_recipient_id_fkey"
            columns: ["recipient_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      order_status_history: {
        Row: {
          changed_by: string | null
          created_at: string
          id: string
          new_status: string
          old_status: string | null
          order_id: string
          reason: string | null
        }
        Insert: {
          changed_by?: string | null
          created_at?: string
          id?: string
          new_status: string
          old_status?: string | null
          order_id: string
          reason?: string | null
        }
        Update: {
          changed_by?: string | null
          created_at?: string
          id?: string
          new_status?: string
          old_status?: string | null
          order_id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "order_status_history_changed_by_fkey"
            columns: ["changed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "order_status_history_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "canteen_orders"
            referencedColumns: ["id"]
          },
        ]
      }
      payments: {
        Row: {
          amount_cents: number
          beneficiary_id: string | null
          created_at: string
          currency: string
          id: string
          idempotency_key: string
          metadata: Json
          payer_id: string | null
          provider: string
          provider_payment_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          amount_cents: number
          beneficiary_id?: string | null
          created_at?: string
          currency?: string
          id?: string
          idempotency_key: string
          metadata?: Json
          payer_id?: string | null
          provider: string
          provider_payment_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          amount_cents?: number
          beneficiary_id?: string | null
          created_at?: string
          currency?: string
          id?: string
          idempotency_key?: string
          metadata?: Json
          payer_id?: string | null
          provider?: string
          provider_payment_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "payments_beneficiary_id_fkey"
            columns: ["beneficiary_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "payments_payer_id_fkey"
            columns: ["payer_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      permissions: {
        Row: {
          created_at: string
          description: string | null
          id: string
          key: string
          name: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          key: string
          name: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          key?: string
          name?: string
        }
        Relationships: []
      }
      player_records: {
        Row: {
          code_of_conduct_accepted_at: string | null
          created_at: string
          external_registration_ref: string | null
          id: string
          medical_notes: string | null
          photo_consent: boolean | null
          registration_status: string
          season_id: string
          support_notes: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          code_of_conduct_accepted_at?: string | null
          created_at?: string
          external_registration_ref?: string | null
          id?: string
          medical_notes?: string | null
          photo_consent?: boolean | null
          registration_status?: string
          season_id: string
          support_notes?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          code_of_conduct_accepted_at?: string | null
          created_at?: string
          external_registration_ref?: string | null
          id?: string
          medical_notes?: string | null
          photo_consent?: boolean | null
          registration_status?: string
          season_id?: string
          support_notes?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "player_records_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "player_records_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          account_status: string
          communication_email: boolean
          communication_sms: boolean
          created_at: string
          date_of_birth: string | null
          email: string | null
          emergency_contact_name: string | null
          emergency_contact_phone: string | null
          full_name: string
          id: string
          mobile: string | null
          onboarding_completed_at: string | null
          preferred_name: string | null
          privacy_accepted_at: string | null
          relationship_to_club: string | null
          terms_accepted_at: string | null
          updated_at: string
        }
        Insert: {
          account_status?: string
          communication_email?: boolean
          communication_sms?: boolean
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          full_name?: string
          id: string
          mobile?: string | null
          onboarding_completed_at?: string | null
          preferred_name?: string | null
          privacy_accepted_at?: string | null
          relationship_to_club?: string | null
          terms_accepted_at?: string | null
          updated_at?: string
        }
        Update: {
          account_status?: string
          communication_email?: boolean
          communication_sms?: boolean
          created_at?: string
          date_of_birth?: string | null
          email?: string | null
          emergency_contact_name?: string | null
          emergency_contact_phone?: string | null
          full_name?: string
          id?: string
          mobile?: string | null
          onboarding_completed_at?: string | null
          preferred_name?: string | null
          privacy_accepted_at?: string | null
          relationship_to_club?: string | null
          terms_accepted_at?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      role_assignment_history: {
        Row: {
          action: string
          actor_id: string | null
          after_state: Json | null
          assignment_id: string | null
          before_state: Json | null
          created_at: string
          id: string
          reason: string | null
        }
        Insert: {
          action: string
          actor_id?: string | null
          after_state?: Json | null
          assignment_id?: string | null
          before_state?: Json | null
          created_at?: string
          id?: string
          reason?: string | null
        }
        Update: {
          action?: string
          actor_id?: string | null
          after_state?: Json | null
          assignment_id?: string | null
          before_state?: Json | null
          created_at?: string
          id?: string
          reason?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "role_assignment_history_actor_id_fkey"
            columns: ["actor_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_assignment_history_assignment_id_fkey"
            columns: ["assignment_id"]
            isOneToOne: false
            referencedRelation: "user_role_assignments"
            referencedColumns: ["id"]
          },
        ]
      }
      role_permissions: {
        Row: {
          created_at: string
          permission_id: string
          role_id: string
        }
        Insert: {
          created_at?: string
          permission_id: string
          role_id: string
        }
        Update: {
          created_at?: string
          permission_id?: string
          role_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "role_permissions_permission_id_fkey"
            columns: ["permission_id"]
            isOneToOne: false
            referencedRelation: "permissions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "role_catalog"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_permissions_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
        ]
      }
      role_requests: {
        Row: {
          created_at: string
          decision_reason: string | null
          experience: string | null
          id: string
          notes: string | null
          reason: string | null
          relationship_note: string | null
          requested_role_id: string | null
          requester_id: string
          review_note: string | null
          reviewed_at: string | null
          reviewed_by: string | null
          season_id: string | null
          status: string
          submitted_at: string | null
          team_id: string | null
          updated_at: string
          withdrawn_at: string | null
        }
        Insert: {
          created_at?: string
          decision_reason?: string | null
          experience?: string | null
          id?: string
          notes?: string | null
          reason?: string | null
          relationship_note?: string | null
          requested_role_id?: string | null
          requester_id: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          season_id?: string | null
          status?: string
          submitted_at?: string | null
          team_id?: string | null
          updated_at?: string
          withdrawn_at?: string | null
        }
        Update: {
          created_at?: string
          decision_reason?: string | null
          experience?: string | null
          id?: string
          notes?: string | null
          reason?: string | null
          relationship_note?: string | null
          requested_role_id?: string | null
          requester_id?: string
          review_note?: string | null
          reviewed_at?: string | null
          reviewed_by?: string | null
          season_id?: string | null
          status?: string
          submitted_at?: string | null
          team_id?: string | null
          updated_at?: string
          withdrawn_at?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "role_requests_requested_role_id_fkey"
            columns: ["requested_role_id"]
            isOneToOne: false
            referencedRelation: "role_catalog"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_requests_requested_role_id_fkey"
            columns: ["requested_role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_requests_requester_id_fkey"
            columns: ["requester_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_requests_reviewed_by_fkey"
            columns: ["reviewed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_requests_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "role_requests_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      roles: {
        Row: {
          created_at: string
          description: string | null
          id: string
          is_sensitive: boolean
          is_system: boolean
          key: string
          may_request: boolean
          name: string
          requires_season_scope: boolean
          requires_super_admin_approval: boolean
          requires_team_scope: boolean
          sort_order: number
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          is_sensitive?: boolean
          is_system?: boolean
          key: string
          may_request?: boolean
          name: string
          requires_season_scope?: boolean
          requires_super_admin_approval?: boolean
          requires_team_scope?: boolean
          sort_order?: number
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          is_sensitive?: boolean
          is_system?: boolean
          key?: string
          may_request?: boolean
          name?: string
          requires_season_scope?: boolean
          requires_super_admin_approval?: boolean
          requires_team_scope?: boolean
          sort_order?: number
        }
        Relationships: []
      }
      seasons: {
        Row: {
          created_at: string
          ends_on: string
          id: string
          name: string
          starts_on: string
          status: string
          updated_at: string
          year: number
        }
        Insert: {
          created_at?: string
          ends_on: string
          id?: string
          name: string
          starts_on: string
          status?: string
          updated_at?: string
          year: number
        }
        Update: {
          created_at?: string
          ends_on?: string
          id?: string
          name?: string
          starts_on?: string
          status?: string
          updated_at?: string
          year?: number
        }
        Relationships: []
      }
      sponsors: {
        Row: {
          contact_email: string | null
          contact_name: string | null
          created_at: string
          description: string | null
          display_locations: string[]
          display_priority: number
          ends_on: string | null
          id: string
          internal_notes: string | null
          logo_url: string | null
          name: string
          starts_on: string | null
          status: string
          tier: string | null
          updated_at: string
          website_url: string | null
        }
        Insert: {
          contact_email?: string | null
          contact_name?: string | null
          created_at?: string
          description?: string | null
          display_locations?: string[]
          display_priority?: number
          ends_on?: string | null
          id?: string
          internal_notes?: string | null
          logo_url?: string | null
          name: string
          starts_on?: string | null
          status?: string
          tier?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Update: {
          contact_email?: string | null
          contact_name?: string | null
          created_at?: string
          description?: string | null
          display_locations?: string[]
          display_priority?: number
          ends_on?: string | null
          id?: string
          internal_notes?: string | null
          logo_url?: string | null
          name?: string
          starts_on?: string | null
          status?: string
          tier?: string | null
          updated_at?: string
          website_url?: string | null
        }
        Relationships: []
      }
      system_settings: {
        Row: {
          description: string | null
          key: string
          updated_at: string
          updated_by: string | null
          value: Json
        }
        Insert: {
          description?: string | null
          key: string
          updated_at?: string
          updated_by?: string | null
          value: Json
        }
        Update: {
          description?: string | null
          key?: string
          updated_at?: string
          updated_by?: string | null
          value?: Json
        }
        Relationships: [
          {
            foreignKeyName: "system_settings_updated_by_fkey"
            columns: ["updated_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      team_players: {
        Row: {
          created_at: string
          ends_on: string | null
          id: string
          player_id: string
          squad_number: number | null
          starts_on: string | null
          status: string
          team_id: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          ends_on?: string | null
          id?: string
          player_id: string
          squad_number?: number | null
          starts_on?: string | null
          status?: string
          team_id: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          ends_on?: string | null
          id?: string
          player_id?: string
          squad_number?: number | null
          starts_on?: string | null
          status?: string
          team_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_players_player_id_fkey"
            columns: ["player_id"]
            isOneToOne: false
            referencedRelation: "player_records"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_players_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
        ]
      }
      team_staff: {
        Row: {
          created_at: string
          ends_on: string | null
          id: string
          staff_role: string
          starts_on: string | null
          status: string
          team_id: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          ends_on?: string | null
          id?: string
          staff_role: string
          starts_on?: string | null
          status?: string
          team_id: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          ends_on?: string | null
          id?: string
          staff_role?: string
          starts_on?: string | null
          status?: string
          team_id?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "team_staff_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "team_staff_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      teams: {
        Row: {
          age_group_id: string | null
          colour: string | null
          competition_id: string | null
          created_at: string
          division: string | null
          external_fixture_url: string | null
          home_venue_id: string | null
          id: string
          name: string
          season_id: string
          status: string
          training_venue_id: string | null
          updated_at: string
        }
        Insert: {
          age_group_id?: string | null
          colour?: string | null
          competition_id?: string | null
          created_at?: string
          division?: string | null
          external_fixture_url?: string | null
          home_venue_id?: string | null
          id?: string
          name: string
          season_id: string
          status?: string
          training_venue_id?: string | null
          updated_at?: string
        }
        Update: {
          age_group_id?: string | null
          colour?: string | null
          competition_id?: string | null
          created_at?: string
          division?: string | null
          external_fixture_url?: string | null
          home_venue_id?: string | null
          id?: string
          name?: string
          season_id?: string
          status?: string
          training_venue_id?: string | null
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "teams_age_group_id_fkey"
            columns: ["age_group_id"]
            isOneToOne: false
            referencedRelation: "age_groups"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_competition_id_fkey"
            columns: ["competition_id"]
            isOneToOne: false
            referencedRelation: "competitions"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_home_venue_id_fkey"
            columns: ["home_venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "teams_training_venue_id_fkey"
            columns: ["training_venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      training_sessions: {
        Row: {
          created_at: string
          ends_at: string | null
          id: string
          notes: string | null
          starts_at: string
          status: string
          team_id: string | null
          updated_at: string
          venue_id: string | null
        }
        Insert: {
          created_at?: string
          ends_at?: string | null
          id?: string
          notes?: string | null
          starts_at: string
          status?: string
          team_id?: string | null
          updated_at?: string
          venue_id?: string | null
        }
        Update: {
          created_at?: string
          ends_at?: string | null
          id?: string
          notes?: string | null
          starts_at?: string
          status?: string
          team_id?: string | null
          updated_at?: string
          venue_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "training_sessions_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "training_sessions_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      user_role_assignments: {
        Row: {
          assigned_by: string | null
          created_at: string
          ends_at: string | null
          id: string
          reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          role_id: string
          season_id: string | null
          starts_at: string
          status: string
          team_id: string | null
          updated_at: string
          user_id: string
        }
        Insert: {
          assigned_by?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role_id: string
          season_id?: string | null
          starts_at?: string
          status?: string
          team_id?: string | null
          updated_at?: string
          user_id: string
        }
        Update: {
          assigned_by?: string | null
          created_at?: string
          ends_at?: string | null
          id?: string
          reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          role_id?: string
          season_id?: string | null
          starts_at?: string
          status?: string
          team_id?: string | null
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_role_assignments_assigned_by_fkey"
            columns: ["assigned_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "role_catalog"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_role_id_fkey"
            columns: ["role_id"]
            isOneToOne: false
            referencedRelation: "roles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_season_id_fkey"
            columns: ["season_id"]
            isOneToOne: false
            referencedRelation: "seasons"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "user_role_assignments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      venues: {
        Row: {
          address: string | null
          created_at: string
          id: string
          name: string
          notes: string | null
          postcode: string | null
          state: string
          suburb: string | null
          updated_at: string
        }
        Insert: {
          address?: string | null
          created_at?: string
          id?: string
          name: string
          notes?: string | null
          postcode?: string | null
          state?: string
          suburb?: string | null
          updated_at?: string
        }
        Update: {
          address?: string | null
          created_at?: string
          id?: string
          name?: string
          notes?: string | null
          postcode?: string | null
          state?: string
          suburb?: string | null
          updated_at?: string
        }
        Relationships: []
      }
      volunteer_assignments: {
        Row: {
          checked_in_at: string | null
          completed_at: string | null
          created_at: string
          id: string
          shift_id: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          checked_in_at?: string | null
          completed_at?: string | null
          created_at?: string
          id?: string
          shift_id: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          checked_in_at?: string | null
          completed_at?: string | null
          created_at?: string
          id?: string
          shift_id?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "volunteer_assignments_shift_id_fkey"
            columns: ["shift_id"]
            isOneToOne: false
            referencedRelation: "volunteer_shifts"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_assignments_user_id_fkey"
            columns: ["user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      volunteer_opportunities: {
        Row: {
          created_at: string
          description: string | null
          id: string
          opportunity_type: string
          required_permission: string | null
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          opportunity_type: string
          required_permission?: string | null
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          opportunity_type?: string
          required_permission?: string | null
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: []
      }
      volunteer_shifts: {
        Row: {
          capacity: number
          created_at: string
          ends_at: string | null
          id: string
          opportunity_id: string
          starts_at: string
          status: string
          updated_at: string
          venue_id: string | null
        }
        Insert: {
          capacity?: number
          created_at?: string
          ends_at?: string | null
          id?: string
          opportunity_id: string
          starts_at: string
          status?: string
          updated_at?: string
          venue_id?: string | null
        }
        Update: {
          capacity?: number
          created_at?: string
          ends_at?: string | null
          id?: string
          opportunity_id?: string
          starts_at?: string
          status?: string
          updated_at?: string
          venue_id?: string | null
        }
        Relationships: [
          {
            foreignKeyName: "volunteer_shifts_opportunity_id_fkey"
            columns: ["opportunity_id"]
            isOneToOne: false
            referencedRelation: "volunteer_opportunities"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "volunteer_shifts_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "venues"
            referencedColumns: ["id"]
          },
        ]
      }
      voucher_issuances: {
        Row: {
          allowed_category_ids: string[]
          allowed_product_ids: string[]
          beneficiary_id: string | null
          claimed_at: string | null
          created_at: string
          expires_at: string | null
          family_id: string | null
          id: string
          issue_reason: string | null
          issued_by: string | null
          original_value_cents: number
          redemption_code: string | null
          redemption_count: number
          redemption_limit: number
          remaining_value_cents: number
          revocation_reason: string | null
          revoked_at: string | null
          revoked_by: string | null
          status: string
          team_id: string | null
          token_hash: string
          updated_at: string
          valid_from: string
          venue_id: string | null
          voucher_type: string
        }
        Insert: {
          allowed_category_ids?: string[]
          allowed_product_ids?: string[]
          beneficiary_id?: string | null
          claimed_at?: string | null
          created_at?: string
          expires_at?: string | null
          family_id?: string | null
          id?: string
          issue_reason?: string | null
          issued_by?: string | null
          original_value_cents?: number
          redemption_code?: string | null
          redemption_count?: number
          redemption_limit?: number
          remaining_value_cents?: number
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          team_id?: string | null
          token_hash: string
          updated_at?: string
          valid_from?: string
          venue_id?: string | null
          voucher_type: string
        }
        Update: {
          allowed_category_ids?: string[]
          allowed_product_ids?: string[]
          beneficiary_id?: string | null
          claimed_at?: string | null
          created_at?: string
          expires_at?: string | null
          family_id?: string | null
          id?: string
          issue_reason?: string | null
          issued_by?: string | null
          original_value_cents?: number
          redemption_code?: string | null
          redemption_count?: number
          redemption_limit?: number
          remaining_value_cents?: number
          revocation_reason?: string | null
          revoked_at?: string | null
          revoked_by?: string | null
          status?: string
          team_id?: string | null
          token_hash?: string
          updated_at?: string
          valid_from?: string
          venue_id?: string | null
          voucher_type?: string
        }
        Relationships: [
          {
            foreignKeyName: "voucher_issuances_beneficiary_id_fkey"
            columns: ["beneficiary_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_issuances_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_issuances_issued_by_fkey"
            columns: ["issued_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_issuances_revoked_by_fkey"
            columns: ["revoked_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_issuances_team_id_fkey"
            columns: ["team_id"]
            isOneToOne: false
            referencedRelation: "teams"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_issuances_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "canteen_venues"
            referencedColumns: ["id"]
          },
        ]
      }
      voucher_redemptions: {
        Row: {
          amount_cents: number
          created_at: string
          device_label: string | null
          id: string
          order_id: string | null
          redeemed_by: string
          status: string
          venue_id: string | null
          voucher_id: string
        }
        Insert: {
          amount_cents: number
          created_at?: string
          device_label?: string | null
          id?: string
          order_id?: string | null
          redeemed_by: string
          status?: string
          venue_id?: string | null
          voucher_id: string
        }
        Update: {
          amount_cents?: number
          created_at?: string
          device_label?: string | null
          id?: string
          order_id?: string | null
          redeemed_by?: string
          status?: string
          venue_id?: string | null
          voucher_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "voucher_redemptions_order_id_fkey"
            columns: ["order_id"]
            isOneToOne: false
            referencedRelation: "canteen_orders"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_redemptions_redeemed_by_fkey"
            columns: ["redeemed_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_redemptions_venue_id_fkey"
            columns: ["venue_id"]
            isOneToOne: false
            referencedRelation: "canteen_venues"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_redemptions_voucher_id_fkey"
            columns: ["voucher_id"]
            isOneToOne: false
            referencedRelation: "voucher_issuances"
            referencedColumns: ["id"]
          },
        ]
      }
      voucher_reversals: {
        Row: {
          amount_cents: number
          authorised_by: string
          created_at: string
          id: string
          reason: string
          redemption_id: string
        }
        Insert: {
          amount_cents: number
          authorised_by: string
          created_at?: string
          id?: string
          reason: string
          redemption_id: string
        }
        Update: {
          amount_cents?: number
          authorised_by?: string
          created_at?: string
          id?: string
          reason?: string
          redemption_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "voucher_reversals_authorised_by_fkey"
            columns: ["authorised_by"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "voucher_reversals_redemption_id_fkey"
            columns: ["redemption_id"]
            isOneToOne: false
            referencedRelation: "voucher_redemptions"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_accounts: {
        Row: {
          account_type: string
          created_at: string
          family_id: string | null
          id: string
          owner_id: string | null
          status: string
          updated_at: string
        }
        Insert: {
          account_type?: string
          created_at?: string
          family_id?: string | null
          id?: string
          owner_id?: string | null
          status?: string
          updated_at?: string
        }
        Update: {
          account_type?: string
          created_at?: string
          family_id?: string | null
          id?: string
          owner_id?: string | null
          status?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_accounts_family_id_fkey"
            columns: ["family_id"]
            isOneToOne: false
            referencedRelation: "families"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_accounts_owner_id_fkey"
            columns: ["owner_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
        ]
      }
      wallet_ledger_entries: {
        Row: {
          amount_cents: number
          beneficiary_id: string | null
          created_at: string
          description: string | null
          direction: string
          id: string
          idempotency_key: string
          initiating_user_id: string | null
          related_entity_id: string | null
          related_entity_type: string | null
          reversal_of: string | null
          transaction_type: string
          wallet_account_id: string
        }
        Insert: {
          amount_cents: number
          beneficiary_id?: string | null
          created_at?: string
          description?: string | null
          direction: string
          id?: string
          idempotency_key: string
          initiating_user_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          reversal_of?: string | null
          transaction_type: string
          wallet_account_id: string
        }
        Update: {
          amount_cents?: number
          beneficiary_id?: string | null
          created_at?: string
          description?: string | null
          direction?: string
          id?: string
          idempotency_key?: string
          initiating_user_id?: string | null
          related_entity_id?: string | null
          related_entity_type?: string | null
          reversal_of?: string | null
          transaction_type?: string
          wallet_account_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "wallet_ledger_entries_beneficiary_id_fkey"
            columns: ["beneficiary_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_entries_initiating_user_id_fkey"
            columns: ["initiating_user_id"]
            isOneToOne: false
            referencedRelation: "profiles"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_entries_reversal_of_fkey"
            columns: ["reversal_of"]
            isOneToOne: false
            referencedRelation: "wallet_ledger_entries"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "wallet_ledger_entries_wallet_account_id_fkey"
            columns: ["wallet_account_id"]
            isOneToOne: false
            referencedRelation: "wallet_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Views: {
      role_catalog: {
        Row: {
          description: string | null
          id: string | null
          is_sensitive: boolean | null
          is_system: boolean | null
          key: string | null
          may_request: boolean | null
          name: string | null
          permissions: Json | null
          requires_season_scope: boolean | null
          requires_super_admin_approval: boolean | null
          requires_team_scope: boolean | null
          sort_order: number | null
        }
        Relationships: []
      }
      wallet_balances: {
        Row: {
          balance_cents: number | null
          wallet_account_id: string | null
        }
        Relationships: [
          {
            foreignKeyName: "wallet_ledger_entries_wallet_account_id_fkey"
            columns: ["wallet_account_id"]
            isOneToOne: false
            referencedRelation: "wallet_accounts"
            referencedColumns: ["id"]
          },
        ]
      }
    }
    Functions: {
      admin_dashboard_summary: { Args: never; Returns: Json }
      assign_user_role: {
        Args: {
          assignment_reason?: string
          ends_at?: string
          starts_at?: string
          target_role_id: string
          target_season_id?: string
          target_team_id?: string
          target_user_id: string
        }
        Returns: string
      }
      has_permission: {
        Args: {
          permission_key: string
          target_season_id?: string
          target_team_id?: string
        }
        Returns: boolean
      }
      redeem_voucher: {
        Args: {
          device_label?: string
          redeem_amount_cents: number
          redeem_order_id?: string
          redeem_venue_id: string
          redemption_token: string
        }
        Returns: {
          redemption_id: string
          remaining_value_cents: number
          result: string
          voucher_id: string
        }[]
      }
      request_role: {
        Args: {
          request_experience?: string
          request_notes?: string
          request_reason?: string
          requested_role_id: string
          target_season_id?: string
          target_team_id?: string
        }
        Returns: string
      }
      reverse_voucher_redemption: {
        Args: { reason: string; target_redemption_id: string }
        Returns: string
      }
      review_role_request: {
        Args: {
          assignment_ends_at?: string
          assignment_starts_at?: string
          decision: string
          review_reason: string
          target_request_id: string
        }
        Returns: string
      }
      revoke_user_role: {
        Args: { revocation_reason: string; target_assignment_id: string }
        Returns: undefined
      }
      withdraw_role_request: {
        Args: { target_request_id: string; withdrawal_reason?: string }
        Returns: undefined
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
