import { getPublicMediaUrl } from "./media";
import { createSupabaseServerClient } from "./supabase/server";

export type PublicGalleryPhoto = {
  id: string;
  url: string;
  alt: string;
};

export type PublicGalleryAlbum = {
  id: string;
  title: string;
  photos: PublicGalleryPhoto[];
};

type RuntimeContext = {
  cookies: any;
  request: Request;
  locals?: unknown;
  url?: URL;
};

const mapAlbum = (row: any, context: RuntimeContext): PublicGalleryAlbum | null => {
  const photos = [...(row.gallery_photos ?? [])]
    .sort((a, b) => a.sort_order - b.sort_order || String(a.created_at).localeCompare(String(b.created_at)))
    .map((photo, index) => {
      const url = getPublicMediaUrl(photo.object_key, context);
      if (!url) return null;
      return {
        id: photo.id,
        url,
        alt: photo.alt_text || `${row.title}, photo ${index + 1}`
      };
    })
    .filter(Boolean) as PublicGalleryPhoto[];
  if (!row.title || photos.length === 0) return null;
  return { id: row.id, title: row.title, photos };
};

export const fetchPublicGallery = async (context: RuntimeContext): Promise<PublicGalleryAlbum[]> => {
  try {
    const supabase = createSupabaseServerClient(context);
    const { data, error } = await (supabase as any)
      .from("gallery_albums")
      .select("id,title,created_at,gallery_photos(id,object_key,alt_text,sort_order,created_at)")
      .eq("published", true)
      .order("created_at", { ascending: false })
      .limit(60);
    if (error) {
      console.error("Unable to load gallery albums", error);
      return [];
    }
    return (data ?? []).map((row: any) => mapAlbum(row, context)).filter(Boolean) as PublicGalleryAlbum[];
  } catch (error) {
    console.error("Unable to load gallery albums", error);
    return [];
  }
};
