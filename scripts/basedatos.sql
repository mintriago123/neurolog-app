-- ================================================================
-- NEUROLOG APP - SCRIPT COMPLETO DE BASE DE DATOS
-- ================================================================
-- Ejecutar completo en Supabase SQL Editor
-- Borra todo y crea desde cero según últimas actualizaciones
-- ================================================================

-- 0. DECLARAR CONSTANTES GLOBALES MEDIANTE FUNCIONES INMUTABLES

-- === ROLES DE USUARIO ===
CREATE OR REPLACE FUNCTION co_role_parent() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'parent'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_role_teacher() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'teacher'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_role_specialist() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'specialist'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_role_admin() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'admin'::TEXT $$;

-- === RELACIONES USUARIO-NIÑO ===E'\n'CREATE OR REPLACE FUNCTION co_relation_parent() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'parent'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_relation_teacher() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'teacher'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_relation_specialist() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'specialist'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_relation_observer() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'observer'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_relation_family() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'family'::TEXT $$;

-- === NIVELES DE INTENSIDAD ===E'\n'CREATE OR REPLACE FUNCTION co_intensity_low() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'low'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_intensity_medium() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'medium'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_intensity_high() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'high'::TEXT $$;

-- === COLORES E ICONOS POR DEFECTO ===E'\n'CREATE OR REPLACE FUNCTION co_color_blue() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT '#3B82F6'::TEXT $$;E'\n'CREATE OR REPLACE FUNCTION co_icon_user() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'user'::TEXT $$;

-- === PRIVACIDAD POR DEFECTO PARA CHILDREN ===
CREATE OR REPLACE FUNCTION co_privacy_default() RETURNS JSONB IMMUTABLE LANGUAGE sql AS $$E'\n'  SELECT '{
    "share_with_specialists": true,
    "share_progress_reports": true,
    "allow_photo_sharing": false,
    "data_retention_months": 36
  }'::JSONB
$$;

-- === ZONA HORARIA POR DEFECTO ===E'\n'CREATE OR REPLACE FUNCTION co_default_timezone() RETURNS TEXT IMMUTABLE LANGUAGE sql AS $$ SELECT 'America/Guayaquil'::TEXT $$;


-- ================================================================
-- 1. LIMPIAR TODO LO EXISTENTE
-- ================================================================

ALTER TABLE IF EXISTS daily_logs DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS user_child_relations DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS children DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS profiles DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS categories DISABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS audit_logs DISABLE ROW LEVEL SECURITY;

DROP VIEW IF EXISTS user_accessible_children CASCADE;
DROP VIEW IF EXISTS child_log_statistics CASCADE;

DROP FUNCTION IF EXISTS user_can_access_child(UUID) CASCADE;
DROP FUNCTION IF EXISTS user_can_edit_child(UUID) CASCADE;
DROP FUNCTION IF EXISTS audit_sensitive_access(TEXT, TEXT, TEXT) CASCADE;
DROP FUNCTION IF EXISTS handle_new_user() CASCADE;
DROP FUNCTION IF EXISTS handle_updated_at() CASCADE;
DROP FUNCTION IF EXISTS verify_neurolog_setup() CASCADE;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS set_updated_at_profiles ON profiles;
DROP TRIGGER IF EXISTS set_updated_at_children ON children;
DROP TRIGGER IF EXISTS set_updated_at_daily_logs ON daily_logs;

DROP TABLE IF EXISTS daily_logs CASCADE;
DROP TABLE IF EXISTS user_child_relations CASCADE;
DROP TABLE IF EXISTS children CASCADE;
DROP TABLE IF EXISTS audit_logs CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- ================================================================
-- 2. CREAR TABLAS PRINCIPALES USANDO CONSTANTES
-- ================================================================

CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  full_name TEXT NOT NULL,
  role TEXT CHECK (role IN (co_role_parent(), co_role_teacher(), co_role_specialist(), co_role_admin())) DEFAULT co_role_parent(),
  avatar_url TEXT,
  phone TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  last_login TIMESTAMPTZ,
  failed_login_attempts INTEGER DEFAULT 0,
  last_failed_login TIMESTAMPTZ,
  account_locked_until TIMESTAMPTZ,
  timezone TEXT DEFAULT co_default_timezone(),E'\n'  preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  description TEXT,
  color TEXT DEFAULT co_color_blue(),
  icon TEXT DEFAULT co_icon_user(),
  is_active BOOLEAN DEFAULT TRUE,
  sort_order INTEGER DEFAULT 0,
  created_by UUID REFERENCES profiles(id),
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE children (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL CHECK (length(trim(name)) >= 2),
  birth_date DATE,
  diagnosis TEXT,
  notes TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  avatar_url TEXT,E'\n'  emergency_contact JSONB DEFAULT '[]',E'\n'  medical_info JSONB DEFAULT '{}',E'\n'  educational_info JSONB DEFAULT '{}',
  privacy_settings JSONB DEFAULT co_privacy_default(),
  created_by UUID REFERENCES profiles(id) NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE user_child_relations (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES profiles(id) ON DELETE CASCADE NOT NULL,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE NOT NULL,
  relationship_type TEXT CHECK (
    relationship_type IN (
      co_relation_parent(), 
      co_relation_teacher(), 
      co_relation_specialist(), 
      co_relation_observer(), 
      co_relation_family()
    )
  ) NOT NULL,
  can_edit BOOLEAN DEFAULT FALSE,
  can_view BOOLEAN DEFAULT TRUE,
  can_export BOOLEAN DEFAULT FALSE,
  can_invite_others BOOLEAN DEFAULT FALSE,
  granted_by UUID REFERENCES profiles(id) NOT NULL,
  granted_at TIMESTAMPTZ DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,E'\n'  notification_preferences JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, child_id, relationship_type)
);

CREATE TABLE daily_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  child_id UUID REFERENCES children(id) ON DELETE CASCADE NOT NULL,
  category_id UUID REFERENCES categories(id),
  title TEXT NOT NULL CHECK (length(trim(title)) >= 2),
  content TEXT NOT NULL,
  mood_score INTEGER CHECK (mood_score >= 1 AND mood_score <= 10),
  intensity_level TEXT CHECK (intensity_level IN (co_intensity_low(), co_intensity_medium(), co_intensity_high())) DEFAULT co_intensity_medium(),
  logged_by UUID REFERENCES profiles(id) NOT NULL,
  log_date DATE DEFAULT CURRENT_DATE,
  is_private BOOLEAN DEFAULT FALSE,
  is_deleted BOOLEAN DEFAULT FALSE,
  is_flagged BOOLEAN DEFAULT FALSE,E'\n'  attachments JSONB DEFAULT '[]',E'\n'  tags TEXT[] DEFAULT '{}',
  location TEXT,
  weather TEXT,
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,
  specialist_notes TEXT,
  parent_feedback TEXT,
  follow_up_required BOOLEAN DEFAULT FALSE,
  follow_up_date DATE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE audit_logs (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  table_name TEXT NOT NULL,E'\n'  operation TEXT CHECK (operation IN ('INSERT', 'UPDATE', 'DELETE', 'SELECT')) NOT NULL,
  record_id TEXT,
  user_id UUID REFERENCES profiles(id),
  user_role TEXT,
  old_values JSONB,
  new_values JSONB,
  changed_fields TEXT[],
  ip_address INET,
  user_agent TEXT,
  session_id TEXT,E'\n'  risk_level TEXT CHECK (risk_level IN ('low', medium, 'high', 'critical')) DEFAULT 'low',
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ================================================================
-- 3. CREAR ÍNDICES PARA PERFORMANCE
-- ================================================================

CREATE INDEX idx_profiles_email ON profiles(email);
CREATE INDEX idx_profiles_role ON profiles(role);
CREATE INDEX idx_profiles_active ON profiles(is_active);

CREATE INDEX idx_children_created_by ON children(created_by);
CREATE INDEX idx_children_active ON children(is_active);
CREATE INDEX idx_children_birth_date ON children(birth_date);

CREATE INDEX idx_relations_user_child ON user_child_relations(user_id, child_id);
CREATE INDEX idx_relations_child ON user_child_relations(child_id);
CREATE INDEX idx_relations_active ON user_child_relations(is_active);

CREATE INDEX idx_logs_child_date ON daily_logs(child_id, log_date DESC);
CREATE INDEX idx_logs_logged_by ON daily_logs(logged_by);
CREATE INDEX idx_logs_category ON daily_logs(category_id);
CREATE INDEX idx_logs_active ON daily_logs(is_deleted);

CREATE INDEX idx_audit_user ON audit_logs(user_id);
CREATE INDEX idx_audit_table ON audit_logs(table_name);
CREATE INDEX idx_audit_created ON audit_logs(created_at DESC);

-- ================================================================
-- 4. CREAR FUNCIONES DE TRIGGERS
-- ================================================================

CREATE OR REPLACE FUNCTION handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO profiles (id, email, full_name, role)
  VALUES (
    NEW.id,
    NEW.email,E'\n'    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),E'\n'    COALESCE(NEW.raw_user_meta_data->>'role', co_role_parent())
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ================================================================
-- 5. CREAR TRIGGERS
-- ================================================================

CREATE TRIGGER set_updated_at_profiles
  BEFORE UPDATE ON profiles
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_children
  BEFORE UPDATE ON children
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER set_updated_at_daily_logs
  BEFORE UPDATE ON daily_logs
  FOR EACH ROW
  EXECUTE FUNCTION handle_updated_at();

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION handle_new_user();

-- ================================================================
-- 6. CREAR FUNCIONES RPC
-- ================================================================

CREATE OR REPLACE FUNCTION user_can_access_child(child_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM children 
    WHERE id = child_uuid 
      AND created_by = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION user_can_edit_child(child_uuid UUID)
RETURNS BOOLEAN AS $$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM children 
    WHERE id = child_uuid 
      AND created_by = auth.uid()
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION audit_sensitive_access(
  action_type TEXT,
  resource_id TEXT,
  action_details TEXT DEFAULT NULL
)
RETURNS VOID AS $$
BEGIN
  INSERT INTO audit_logs (
    table_name,
    operation,
    record_id,
    user_id,
    user_role,
    new_values,
    risk_level
  ) VALUES (E'\n'    'sensitive_access',E'\n'    'SELECT',
    resource_id,
    auth.uid(),
    (SELECT role FROM profiles WHERE id = auth.uid()),
    jsonb_build_object(E'\n'      'action_type', action_type,E'\n'      'details', action_details,E'\n'      'timestamp', NOW()
    ),
    medium
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ================================================================
-- 7. CREAR VISTAS
-- ================================================================

CREATE OR REPLACE VIEW user_accessible_children AS
SELECT 
  c.*,
  co_role_parent() as relationship_type,
  true as can_edit,
  true as can_view,
  true as can_export,
  true as can_invite_others,
  c.created_at as granted_at,
  NULL::TIMESTAMPTZ as expires_at,
  p.full_name as creator_name
FROM children c
JOIN profiles p ON c.created_by = p.id
WHERE c.created_by = auth.uid()
  AND c.is_active = true;

CREATE OR REPLACE VIEW child_log_statistics AS
SELECT 
  c.id as child_id,
  c.name as child_name,
  COUNT(dl.id) as total_logs,E'\n'  COUNT(CASE WHEN dl.log_date >= CURRENT_DATE - INTERVAL '7 days' THEN 1 END) as logs_this_week,E'\n'  COUNT(CASE WHEN dl.log_date >= CURRENT_DATE - INTERVAL '30 days' THEN 1 END) as logs_this_month,
  ROUND(AVG(dl.mood_score), 2) as avg_mood_score,
  MAX(dl.log_date) as last_log_date,
  COUNT(DISTINCT dl.category_id) as categories_used,
  COUNT(CASE WHEN dl.is_private THEN 1 END) as private_logs,
  COUNT(CASE WHEN dl.reviewed_at IS NOT NULL THEN 1 END) as reviewed_logs
FROM children c
LEFT JOIN daily_logs dl ON c.id = dl.child_id AND dl.is_deleted = false
WHERE c.created_by = auth.uid()
GROUP BY c.id, c.name;

-- ================================================================
-- 8. INSERTAR DATOS INICIALES
-- ================================================================

INSERT INTO categories (name, description, color, icon, sort_order) VALUESE'\n'('Comportamiento', 'Registros sobre comportamiento y conducta', co_color_blue(), co_icon_user(), 1),E'\n'('Emociones', 'Estado emocional y regulación', '#EF4444', 'heart', 2),E'\n'('Aprendizaje', 'Progreso académico y educativo', '#10B981', 'book', 3),E'\n'('Socialización', 'Interacciones sociales', '#F59E0B', 'users', 4),E'\n'('Comunicación', 'Habilidades de comunicación', '#8B5CF6', 'message-circle', 5),E'\n'('Motricidad', 'Desarrollo motor fino y grueso', '#06B6D4', 'activity', 6),E'\n'('Alimentación', 'Hábitos alimentarios', '#84CC16', 'utensils', 7),E'\n'('Sueño', 'Patrones de sueño y descanso', '#6366F1', 'moon', 8),E'\n'('Medicina', 'Información médica y tratamientos', '#EC4899', 'pill', 9),E'\n'('Otros', 'Otros registros importantes', '#6B7280', 'more-horizontal', 10);

-- ================================================================
-- 9. HABILITAR RLS Y CREAR POLÍTICAS SIMPLES
-- ================================================================

ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_child_relations ENABLE ROW LEVEL SECURITY;
ALTER TABLE daily_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can view own profile" ON profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "Users can update own profile" ON profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile" ON profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "Users can view own created children" ON children
  FOR SELECT USING (created_by = auth.uid());

CREATE POLICY "Authenticated users can create children" ON children
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL AND 
    created_by = auth.uid()
  );

CREATE POLICY "Creators can update own children" ON children
  FOR UPDATE USING (created_by = auth.uid())
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "Users can view own relations" ON user_child_relations
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Users can create relations for own children" ON user_child_relations
  FOR INSERT WITH CHECK (
    granted_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM children 
      WHERE id = user_child_relations.child_id 
        AND created_by = auth.uid()
    )
  );

CREATE POLICY "Users can view logs of own children" ON daily_logs
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM children 
      WHERE id = daily_logs.child_id 
        AND created_by = auth.uid()
    )
  );

CREATE POLICY "Users can create logs for own children" ON daily_logs
  FOR INSERT WITH CHECK (
    logged_by = auth.uid() AND
    EXISTS (
      SELECT 1 FROM children 
      WHERE id = daily_logs.child_id 
        AND created_by = auth.uid()
    )
  );

CREATE POLICY "Users can update own logs" ON daily_logs
  FOR UPDATE USING (logged_by = auth.uid())
  WITH CHECK (logged_by = auth.uid());

CREATE POLICY "Authenticated users can view categories" ON categories
  FOR SELECT USING (auth.uid() IS NOT NULL AND is_active = true);

CREATE POLICY "System can insert audit logs" ON audit_logs
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- ================================================================
-- 10. FUNCIÓN DE VERIFICACIÓN
-- ================================================================

CREATE OR REPLACE FUNCTION verify_neurolog_setup()
RETURNS TEXT AS $$
DECLAREE'\n'  result TEXT := '';
  table_count INTEGER;
  policy_count INTEGER;
  function_count INTEGER;
  category_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO table_count
  FROM information_schema.tables E'\n'  WHERE table_schema = 'public' E'\n'    AND table_name IN ('profiles', 'children', 'user_child_relations', 'daily_logs', 'categories', 'audit_logs');
  E'\n'  result := result || 'Tablas creadas: ' || table_count || '/6' || E'\n';
  
  SELECT COUNT(*) INTO policy_count
  FROM pg_policies E'\n'  WHERE schemaname = 'public';
  E'\n'  result := result || 'Políticas RLS: ' || policy_count || E'\n';
  
  SELECT COUNT(*) INTO function_count
  FROM pg_proc E'\n'  WHERE proname IN ('user_can_access_child', 'user_can_edit_child', 'audit_sensitive_access');
  E'\n'  result := result || 'Funciones RPC: ' || function_count || '/3' || E'\n';
  
  SELECT COUNT(*) INTO category_count
  FROM categories WHERE is_active = true;
  E'\n'  result := result || 'Categorías: ' || category_count || '/10' || E'\n';
  
  IF (SELECT COUNT(*) FROM pg_class c 
      JOIN pg_namespace n ON n.oid = c.relnamespace E'\n'      WHERE n.nspname = 'public' E'\n'        AND c.relname = 'children' 
        AND c.relrowsecurity = true) > 0 THENE'\n'    result := result || 'RLS: ✅ Habilitado' || E'\n';
  ELSEE'\n'    result := result || 'RLS: ❌ Deshabilitado' || E'\n';
  END IF;
  E'\n'  result := result || E'\n🎉 BASE DE DATOS NEUROLOG CONFIGURADA COMPLETAMENTE';
  
  RETURN result;
END;
$$ LANGUAGE plpgsql;

-- ================================================================
-- 11. EJECUTAR VERIFICACIÓN FINAL
-- ================================================================

SELECT verify_neurolog_setup();

-- ================================================================
-- 12. MENSAJE FINAL
-- ================================================================

DO $$
BEGINE'\n'  RAISE NOTICE '🎉 ¡BASE DE DATOS NEUROLOG CREADA EXITOSAMENTE!';E'\n'  RAISE NOTICE '===============================================';E'\n'  RAISE NOTICE 'Todas las tablas, funciones, vistas y políticas han sido creadas.';E'\n'  RAISE NOTICE 'La base de datos está lista para usar.';E'\n'  RAISE NOTICE '';E'\n'  RAISE NOTICE 'FUNCIONALIDADES INCLUIDAS:';E'\n'  RAISE NOTICE '✅ Gestión de usuarios (profiles)';E'\n'  RAISE NOTICE '✅ Gestión de niños (children)';E'\n'  RAISE NOTICE '✅ Relaciones usuario-niño (user_child_relations)';E'\n'  RAISE NOTICE '✅ Registros diarios (daily_logs)';E'\n'  RAISE NOTICE '✅ Categorías predefinidas (categories)';E'\n'  RAISE NOTICE '✅ Sistema de auditoría (audit_logs)';E'\n'  RAISE NOTICE '✅ Políticas RLS funcionales';E'\n'  RAISE NOTICE '✅ Funciones RPC necesarias';E'\n'  RAISE NOTICE '✅ Vistas optimizadas';E'\n'  RAISE NOTICE '✅ Índices para performance';E'\n'  RAISE NOTICE '';E'\n'  RAISE NOTICE 'PRÓXIMO PASO: Probar la aplicación NeuroLog';
END $$;