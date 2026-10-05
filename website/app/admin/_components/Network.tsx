"use client";

import { useEffect, useRef, useState } from "react";
import { Card, fmt, getData, Loading, Section, StatCard, STACK_SECTIONS, TILE } from "./lib";
import { useOpenUser } from "./Drilldown";
import { handle, useAdjacency, type FriendNetwork, type UserLocations } from "./networkCanvas";
import { NetworkWeb } from "./NetworkWeb";
import { NetworkTree } from "./NetworkTree";
import { NetworkMap } from "./NetworkMap";

/**
 * Who is friends with whom, and where people walk.
 *
 * The web and the tree share one payload (`/network`): the tree is just one
 * person's neighbourhood of the same graph, so a click in the web opens it
 * with no second fetch. The map has its own (`/network/locations`), since it
 * reads GPS routes and is cached longer.
 */
export function NetworkTab() {
  const openUser = useOpenUser();
  const [net, setNet] = useState<FriendNetwork | null>(null);
  const [loc, setLoc] = useState<UserLocations | null>(null);
  const [netErr, setNetErr] = useState<string | null>(null);
  const [locErr, setLocErr] = useState<string | null>(null);
  const [treeTarget, setTreeTarget] = useState<number | null>(null);
  const treeRef = useRef<HTMLDivElement>(null);
  const adj = useAdjacency(net);

  useEffect(() => {
    getData<FriendNetwork>("network")
      .then(setNet)
      .catch((e) => {
        if (e?.message !== "unauthorized") setNetErr("Failed to load the friend network.");
      });
    getData<UserLocations>("network/locations")
      .then(setLoc)
      .catch((e) => {
        if (e?.message !== "unauthorized") setLocErr("Failed to load locations.");
      });
  }, []);

  // The tree starts on the biggest group's hub: the most connected person in
  // the most connected part of the app.
  const target = treeTarget ?? (net && net.groups.length ? net.groups[0].hub : null);

  const openTree = (i: number) => {
    setTreeTarget(i);
    requestAnimationFrame(() =>
      treeRef.current?.scrollIntoView({ behavior: "smooth", block: "start" }),
    );
  };

  const s = net?.summary;
  const biggest = net?.groups[0];

  return (
    <div className={STACK_SECTIONS}>
      <Section
        title="Friend web"
        hint="Every dot is a person with at least one friend; every line is a friendship. Colours are friend groups — people more connected to each other than to anyone else. Drag people or the background, scroll or pinch to zoom, click someone to light up their friends."
      >
        {s && net && (
          <div className={`grid grid-cols-2 lg:grid-cols-4 ${TILE}`}>
            <StatCard
              label="People with friends"
              value={fmt(s.connected_users)}
              sub={`of ${fmt(s.total_users)} · ${fmt(s.isolated_users)} with none yet`}
            />
            <StatCard
              label="Friendships"
              value={fmt(s.friendships)}
              sub={`median ${s.median_friends} each · most ${s.max_friends} · ${fmt(s.pending_requests)} requests pending`}
            />
            <StatCard
              label="Friend groups"
              value={fmt(s.groups)}
              sub={
                biggest
                  ? `biggest: ${handle(net.nodes[biggest.hub])}'s, ${biggest.size} people`
                  : undefined
              }
            />
            <StatCard
              label="Separate networks"
              value={fmt(s.islands)}
              sub={`no friendship links one to another · the largest holds ${fmt(s.largest_island)}`}
            />
          </div>
        )}
        {netErr ? (
          <Card>{netErr}</Card>
        ) : !net ? (
          <Card>
            <Loading label="Loading the friend network…" />
          </Card>
        ) : net.nodes.length === 0 ? (
          <Card>
            <p className="text-sm text-white/40">No friendships yet.</p>
          </Card>
        ) : (
          <NetworkWeb net={net} adj={adj} onOpenTree={openTree} onOpenProfile={openUser} />
        )}
      </Section>

      <div ref={treeRef} className="scroll-mt-32">
        <Section
          title="Friend tree"
          hint="One person's friends and friends-of-friends, laid out by when each joined. The bottom row is people one introduction away: friends of their friends who aren't their friends yet."
        >
          {net && target !== null ? (
            <NetworkTree
              net={net}
              adj={adj}
              target={target}
              onTarget={setTreeTarget}
              onOpenProfile={openUser}
            />
          ) : netErr ? (
            <Card>{netErr}</Card>
          ) : net ? (
            <Card>
              <p className="text-sm text-white/40">No friendships yet.</p>
            </Card>
          ) : (
            <Card>
              <Loading />
            </Card>
          )}
        </Section>
      </div>

      <Section
        title="Where people walk"
        hint="Placed by their GPS routes — the only location the app records — in ~17-mile squares. Scroll or pinch to zoom; close in, each square shows its count."
      >
        {locErr ? (
          <Card>{locErr}</Card>
        ) : !loc ? (
          <Card>
            <Loading label="Loading the map…" />
          </Card>
        ) : (
          <NetworkMap loc={loc} />
        )}
      </Section>
    </div>
  );
}
