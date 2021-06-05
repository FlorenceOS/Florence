usingnamespace @import("root").preamble;

/// Features that should be enabled in the code for the red black tree
pub const Features = struct {
    enable_iterators_cache: bool,
    enable_kth_queries: bool,
    enable_not_associatve_augment: bool,
};

/// Config for red black tree. Includes enabled features and callbacks for comparison and augmenting
pub const Config = struct {
    augment_callback: ?type,
    comparator: type,
    features: Features,
};

/// Color type
pub const Color = enum { red, black };

/// Node in the red black tree
pub fn Node(comptime features: Features) type {
    return struct {
        /// Node's descendants (desc[0] - left, desc[1] - right)
        desc: [2]?*@This(),
        /// Node's parent
        par: ?*@This(),
        // Number of nodes in the subtree
        subtree_size: if (features.enable_kth_queries) usize else void,
        /// Node color
        color: Color,
        /// Data for iterator extension
        iterators: if (features.enable_iterators_cache) [2]?*@This() else void,

        /// Create empty node
        fn init() @This() {
            return .{
                .desc = .{ null, null },
                .iterators = if (features.enable_iterators_cache) .{ null, null } else {},
                .par = null,
                .subtree_size = if (features.enable_kth_queries) 1 else {},
                .color = .red,
            };
        }

        /// Query direction from parent
        fn direction(self: *const @This()) u1 {
            return if (self.par) |parent| @boolToInt(parent.desc[1] == self) else 0;
        }

        // If `self` if null, return black color, otherwise return color of `self`
        fn colorOrBlack(self: ?*const @This()) Color {
            return (self orelse return .black).color;
        }

        // Get node's sibling, or return null if there is none
        fn sibling(self: *const @This()) ?*@This() {
            const pos = self.direction();
            return if (self.par) |parent| parent.desc[1 - pos] else null;
        }
    };
}

/// Red black tree itself
pub fn Tree(comptime T: type, comptime member_name: []const u8, comptime cfg: Config) type {
    const NodeType = Node(cfg.features);
    const enable_iterators_cache = cfg.features.enable_iterators_cache;
    const enable_kth_queries = cfg.features.enable_kth_queries;
    // Make sure that comparator type is valid
    if (!@hasDecl(cfg.comparator, "compare")) {
        @compileError("Comparator should define \"compare\" function");
    }
    const expected_cmp_type = fn (*const cfg.comparator, *const T, *const T) bool;
    if (!(@TypeOf(cfg.comparator.compare) == expected_cmp_type)) {
        @compileError("Invalid type of \"compare\" function");
    }
    // Make sure that augment callback is valid
    if (cfg.augment_callback) |augment_callback| {
        if (!@hasDecl(augment_callback, "augment")) {
            @compileError("Augment callback should define \"augment\" function");
        }
        const expected_augment_callback_type = fn (*const augment_callback, *T) bool;
        if (!(@TypeOf(augment_callback.augment) == expected_cmp_type)) {
            @compileError("Invalid type of \"augment\" function");
        }
    }
    return struct {
        /// Used inside extensions
        const TreeType = @This();
        /// root of the tree
        root: ?*NodeType,
        /// comparator used for insertions/deletitions
        comparator: cfg.comparator,
        /// callback used for augmenting
        augment_callback: if (cfg.augment_callback) |callback| callback else void,
        /// size of the tree,
        size: usize,
        /// iterators extension data and functions
        iterators: if (enable_iterators_cache)
            struct {
                ends: [2]?*NodeType,
                /// First element in a tree
                pub fn first(self: *const @This()) ?*T {
                    return TreeType.nodeToRefOpt(self.ends[0]);
                }

                /// Last element in a tree
                pub fn last(self: *const @This()) ?*T {
                    return TreeType.nodeToRefOpt(self.ends[1]);
                }

                /// Get the next node in left-to-right order
                pub fn next(_: *const @This(), ref: *T) ?*T {
                    return TreeType.nodeToRefOpt(TreeType.refToNode(ref).iterators[1]);
                }

                /// Get the previous node in left-to-right order
                pub fn prev(_: *const @This(), ref: *T) ?*T {
                    return TreeType.nodeToRefOpt(TreeType.refToNode(ref).iterators[0]);
                }
            }
        else
            void,
        /// kth queries extensions
        kth: if (enable_kth_queries)
            struct {
                /// Fix zero sized pointer issue in zig compiler
                /// "the issue is: kth is a zero-size type, so the pointer to kth is
                /// itself zero-sized, and therefore has no data"
                /// Issue in zig lang repository: "https://github.com/ziglang/zig/issues/1530"
                temp_fix: u8,
                /// Get subtree size
                pub fn getSubtreeSize(node: ?*const NodeType) usize {
                    return if (node) |node_nonnull| node_nonnull.subtree_size else 0;
                }

                /// Get kth element
                pub fn at(self: *const @This(), index: usize) ?*T {
                    // Done so that user can write `tree.kth.at(n)`
                    const tree = @fieldParentPtr(TreeType, "kth", self);
                    // The method used here is to perform descent
                    // We keep record of index at which we want to retrive
                    // element in `offset_needed` variable
                    var current_nullable = tree.root;
                    var offset_needed = index;
                    while (current_nullable) |current| {
                        if (getSubtreeSize(current.desc[0]) == offset_needed) {
                            // If left subtree has exactly as many nodes as we need,
                            // current node is node we are searching for
                            // (current node is at <left subtree size> index in its subtree)
                            return nodeToRef(current);
                        } else if (getSubtreeSize(current.desc[0]) > offset_needed) {
                            // If left subtree has more nodes than we need,
                            // nth element should be in the left subtree
                            current_nullable = current.desc[0];
                        } else {
                            // If `offset_needed` is greater than the amount of nodes in the
                            // right subtree, we need to search in the right subtree
                            // The index is now different, as we want to skip left subtree +
                            // current node
                            offset_needed -= (1 + getSubtreeSize(current.desc[0]));
                            current_nullable = current.desc[1];
                        }
                    }
                    // Tree is small and there is no nth node
                    return null;
                }
            }
        else
            void,

        /// Given the pointer to the element, returns previous element in the tree
        pub fn right(node: *const T) ?*T {
            return nodeToRef(refToNode(node).desc[0]);
        }

        /// Given the pointer to the element, returns next element in the tree
        pub fn left(node: *const T) ?*T {
            return nodeToRef(refToNode(node).desc[1]);
        }

        /// Convert reference to red black tree node to reference to T
        pub fn nodeToRef(node: *NodeType) *T {
            return @fieldParentPtr(T, member_name, node);
        }

        /// Convert reference to T to reference to red black tree node
        pub fn refToNode(ref: *T) *NodeType {
            return &@field(ref, member_name);
        }

        /// Convert nullable reference to red black tree node to nullable reference to T
        pub fn nodeToRefOpt(node: ?*NodeType) ?*T {
            return if (node) |node_nonnull| nodeToRef(node_nonnull) else null;
        }

        /// Convert nullable reference to T to nullable reference to red black tree node
        pub fn refToNodeOpt(ref: ?*T) ?*NodeType {
            return if (ref) |ref_nonnull| refToNode(ref_nonnull) else null;
        }

        // u1 is returned to simplify accesses in `desc` and `neighbours` arrays
        fn compareNodes(self: *const @This(), l: *NodeType, r: *NodeType) u1 {
            return @boolToInt(self.comparator.compare(nodeToRef(l), nodeToRef(r)));
        }

        /// Call augment callback on a single node
        fn updateParentAugment(node: *NodeType) bool {
            if (cfg.augment_callback) |_| {
                return self.augment_callback.augment(refToNode(node));
            }
            return false;
        }

        /// Propogate augment callback
        fn updatePathAugment(node: *NodeType) void {
            var current_nullable: ?*NodeType = node;
            while (current_nullable) |current| {
                if (!updateParentAugment(current)) {
                    return;
                }
                current_nullable = current.par;
            }
        }

        /// Update data used for kth extension locally
        fn updateParentSubtreeSize(node: *NodeType) bool {
            if (enable_kth_queries) {
                var subtree_size: usize = 1;
                if (node.desc[0]) |l| {
                    subtree_size += l.subtree_size;
                }
                if (node.desc[1]) |r| {
                    subtree_size += r.subtree_size;
                }
                if (node.subtree_size != subtree_size) {
                    node.subtree_size = subtree_size;
                    // subtree size has changed, propogate to parent
                    return true;
                }
                // subtree size has not changed, don't propogate to parent
                return false;
            }
            return false;
        }

        /// Propogate subtree sizes updates
        fn updatePathSubtreeSizes(node: *NodeType) void {
            var current_nullable: ?*NodeType = node;
            while (current_nullable) |current| {
                if (!updateParentSubtreeSize(current)) {
                    return;
                }
                current_nullable = current.par;
            }
        }

        /// Rotate subtree at `node` in `dir` direction. Tree is passed because
        /// root updates might be needed
        fn rotate(self: *@This(), node: *NodeType, dir: u1) void {
            const new_top_nullable = node.desc[1 - dir];
            const new_top = new_top_nullable.?;
            const mid = new_top.desc[dir];
            const parent = node.par;
            const pos = node.direction();
            node.desc[1 - dir] = mid;
            if (mid) |mid_nonnull| {
                mid_nonnull.par = node;
            }
            new_top.desc[dir] = node;
            node.par = new_top;
            if (parent) |parent_nonnull| {
                parent_nonnull.desc[pos] = new_top;
                new_top.par = parent;
            } else {
                self.root = new_top;
                new_top.par = null;
                new_top.color = .black;
            }
            _ = updateParentSubtreeSize(node);
            _ = updateParentAugment(node);
            // If augment function is not associative,
            // we need to call aggregate on parent too
            if (cfg.features.enable_not_associatve_augment) {
                _ = updateParentSubtreeSize(new_top);
                _ = updateParentAugment(new_top);
                if (parent) |parent_nonnull| {
                    updatePathSubtreeSizes(parent_nonnull);
                    updatePathAugment(parent_nonnull);
                }
            } else {
                _ = updateParentSubtreeSize(new_top);
                _ = updateParentAugment(new_top);
            }
        }

        fn fixInsertion(self: *@This(), node: *NodeType) void {
            // Situation we are trying to fix: double red
            // According to red black tree invariants, only
            //
            //           G(X)       Cast
            //          /   \       C - current node   (R) - red
            //       P(R)   U(X)    P - parent         (B) - black
            //      /               G - grandparent    (X) - color unknown
            //   C(R)               U - uncle
            //
            var current: *NodeType = node;
            while (current.par) |parent| {
                // if parent is black, there is no double red. See diagram above.
                if (parent.color == .black) {
                    break;
                }
                const uncle = parent.sibling();
                // Root has to be black, and as parent is red, grandparent should exist
                const grandparent = parent.par.?;
                const dir = current.direction();
                if (NodeType.colorOrBlack(uncle) == .black) {
                    const parent_dir = parent.direction();
                    if (parent_dir == dir) {
                        //           G(B)                   P(B)
                        //          /   \                  /   \
                        //       P(R)   U(B)  ------>   C(R)   G(R)
                        //      /                                \
                        //   C(R)                                U(B)
                        //
                        // If uncle is black, grandparent has to be black, as parent is red.
                        // If grandparent was red, both of its children would have to be black,
                        // but parent is red.
                        // Grandparent color is updated later. Black height on path to B has not
                        // changed
                        // (before: grandparent black and uncle black, now P black and U black)
                        self.rotate(grandparent, 1 - dir);
                        parent.color = .black;
                    } else {
                        //          G(B)                  G(B)               C(B)
                        //        /     \                /   \              /   \
                        //      P(R)   U(B)   ---->    C(R)  U(B)   --->  P(R)  G(R)
                        //        \                   /                          \
                        //         C(R)             P(R)                         U(B)
                        //
                        // Final recoloring of grandparent is done on line 339 as well.
                        // Black height on path to U has not changed
                        // (before: G and U black, after: C and U black)
                        // On the old track in P direction, nothing has changed as well
                        self.rotate(parent, 1 - dir);
                        self.rotate(grandparent, dir);
                        current.color = .black;
                    }
                    grandparent.color = .red;
                    break;
                } else {
                    //           G(B)                  G(R) <- potential double red fix needed
                    //         /     \               /     \
                    //       P(R)   U(R)   ---->   P(B)    U(B)
                    //      /                     /
                    //   C(R)                   C(R)
                    //
                    // The solution for the case in which uncle is red is to "push blackness down".
                    // We recolor parent and uncle to black and grandparent to red.
                    // It is easy to verify that black heights for all nodes have not changed.
                    // The only problem we have encountered is that grandparent's parent is red.
                    // If that is the case, we can have double red again. As such, we continue
                    // fixing by setting `current` to grandparent

                    // If uncle is red, it is not null
                    const uncle_nonnull = uncle.?;
                    parent.color = .black;
                    uncle_nonnull.color = .black;
                    grandparent.color = .red;
                    current = grandparent;
                }
            }
            // We were inserting node, so root is not null
            self.root.?.color = .black;
        }

        /// Attaches node that is not yet in tree to the node in tree
        fn attachNode(self: *@This(), parent: *NodeType, node: *NodeType, pos: u1) void {
            parent.desc[pos] = node;
            node.par = parent;
            if (enable_iterators_cache) {
                // parent is a successor/predecessor
                // next_in_attach_dir has on opposite role, i.e. if parent is predecessor
                // it will be successor and vice versa

                // connecting next_in_attach_dir and node using iterators
                const next_in_attach_dir = parent.iterators[pos];
                node.iterators[pos] = next_in_attach_dir;
                // it may not exist tho, so it would not hurt to check if first/last pointers
                // shoul be updated
                if (next_in_attach_dir) |neighbour| {
                    neighbour.iterators[1 - pos] = node;
                } else {
                    self.iterators.ends[pos] = node;
                }
                // connecting parent and node with iterators
                parent.iterators[pos] = node;
                node.iterators[1 - pos] = parent;
            }
        }

        /// Helper for `insert`
        fn insertImpl(self: *@This(), node: *NodeType) void {
            // See node constructor. All values are zeroed and color is set to .red
            node.* = NodeType.init();
            // Check if node is root
            if (self.root) |root| {
                // While doing descent, we remember previous node, so that when current node
                // becomes null, we will know which node we should attach our new node to
                var prev: *NodeType = undefined;
                var current: ?*NodeType = root;
                // Last direction is remembered in order to determine whether
                // new node should be left or right child
                var last_direction: u1 = 0;
                while (current) |current_nonnull| {
                    // compareNodes already returns direction in which we should go
                    last_direction = self.compareNodes(node, current_nonnull);
                    prev = current_nonnull;
                    current = current_nonnull.desc[last_direction];
                }
                // Attach node to prev.
                self.attachNode(prev, node, last_direction);
                self.fixInsertion(node);
                updatePathSubtreeSizes(prev);
                updatePathAugment(prev);
            } else {
                // If node is root, our job is easy
                node.color = .black;
                if (enable_iterators_cache) {
                    self.iterators.ends[0] = node;
                    self.iterators.ends[1] = node;
                }
                self.root = node;
            }
            self.size += 1;
        }

        /// Insert node in tree
        pub fn insert(self: *@This(), node: *T) void {
            self.insertImpl(refToNode(node));
        }

        /// Get other node to delete if `node` has two children
        fn findReplacement(node: *NodeType) *NodeType {
            // Replacement is only calculated on nodes with two children
            var current: *NodeType = node.desc[0].?;
            while (current.desc[1]) |next| {
                current = next;
            }
            return current;
        }

        /// Helper for iterators swap. Changes pointers to `node` to pointers to `replacement`
        fn replaceInIterList(
            iterators: *[2]?*NodeType,
            node: *NodeType,
            replacement: *NodeType,
        ) void {
            if (iterators[0] == node) {
                iterators[0] = replacement;
            }
            if (iterators[1] == node) {
                iterators[1] = replacement;
            }
        }

        /// Second helper for iterators swap. Changes ends of the tree from `node`
        /// to `replacement` if corresponding element in `iterators` is null. Used to update tree
        /// iterator chain ends
        fn updateEndPointers(
            self: *@This(),
            iterators: *[2]?*NodeType,
            replacement: *NodeType,
        ) void {
            if (iterators[0]) |l| {
                l.iterators[1] = replacement;
            } else {
                self.iterators.ends[0] = replacement;
            }
            if (iterators[1]) |r| {
                r.iterators[0] = replacement;
            } else {
                self.iterators.ends[1] = replacement;
            }
        }

        /// Swap node with replacement found by `findReplacement`
        /// Does that without relocating node's data
        fn pointerSwap(self: *@This(), node: *NodeType, replacement: *NodeType) void {
            // Node should have two children
            std.debug.assert(node.desc[0] != null);
            std.debug.assert(node.desc[1] != null);
            // Swap nodes colors
            const node_color = node.color;
            node.color = replacement.color;
            replacement.color = node_color;
            // Cache node's pointers
            const node_parent = node.par;
            const replacement_parent = replacement.par;
            const node_children = node.desc;
            const replacement_children = replacement.desc;
            // Cache node's positions
            const node_dir = node.direction();
            const replacement_dir = replacement.direction();
            // Check out `findReplacement`. Proof left for the reader
            std.debug.assert(replacement_children[1] == null);
            // Swap children pointers and set node's parent
            if (node.desc[0] == replacement) {
                // Case 1: replacement is left child of node
                // as findReplacement only
                // Swap children
                node.desc = replacement_children;
                // As `replaced_children` right parent is null (see assert),
                // only check left children.
                if (replacement_children[0]) |repl_child| {
                    repl_child.par = node;
                }
                // Replacement's left child should be node now
                // as roles have been exchanged
                replacement.desc[0] = node;
                // as node and replacement swapped roles
                // node's parent is now replacement
                node.par = replacement;
                // right child of replacement remains unchanged from node
                replacement.desc[1] = node_children[1];
                if (node_children[1]) |node_child| {
                    node_child.par = replacement;
                }
            } else {
                // Case 2: replacement is not a child of node
                // swap children
                replacement.desc = node_children;
                // They are both not null, as node has two children
                node_children[0].?.par = replacement;
                node_children[1].?.par = replacement;

                node.desc = replacement_children;
                // Replacement can only have left child.
                // Update its parent if needed
                if (replacement_children[0]) |repl_child| {
                    repl_child.par = node;
                }

                node.par = replacement_parent;
                // Replacement parent should exist
                // As it is down the tree from node
                replacement_parent.?.desc[replacement_dir] = node;
            }
            // Update parent link for replacement
            replacement.par = node_parent;
            if (node_parent) |parent| {
                // Node wasn't root. Change link from parent
                parent.desc[node_dir] = replacement;
            } else {
                // Node was root. Set tree root to replacement
                self.root = replacement;
                replacement.par = null;
                replacement.color = .black;
            }
            // Swap iterators if needed
            if (enable_iterators_cache) {
                var node_iterators = node.iterators;
                var replacement_iterators = replacement.iterators;
                // If something poitned to replacement, it should now point to node
                // and vise versa
                replaceInIterList(&node_iterators, replacement, node);
                replaceInIterList(&replacement_iterators, node, replacement);
                self.updateEndPointers(&node_iterators, replacement);
                self.updateEndPointers(&replacement_iterators, node);
                node.iterators = replacement_iterators;
                replacement.iterators = node_iterators;
            }
            // Swap subtree elements count if needed
            if (enable_kth_queries) {
                const node_subtree_size = node.subtree_size;
                node.subtree_size = replacement.subtree_size;
                replacement.subtree_size = node_subtree_size;
            }
            // Call aggregate updates if needed
            // Subtree sizes are already updated
            updatePathAugment(replacement);
        }
        /// Ensure that node to delete has at most one child
        // TODO: add option to use value swap in config
        fn replaceIfNeeded(self: *@This(), node: *NodeType) void {
            if (node.desc[0] != null and node.desc[1] != null) {
                const replacement = findReplacement(node);
                pointerSwap(self, node, replacement);
            }
        }

        /// Cut from iterators list if enabled
        fn cutFromIterList(self: *@This(), node: *NodeType) void {
            if (enable_iterators_cache) {
                if (node.iterators[0]) |l| {
                    l.iterators[1] = node.iterators[1];
                } else {
                    self.iterators.ends[0] = node.iterators[1];
                    if (node.iterators[1]) |r| {
                        r.iterators[0] = null;
                    }
                }
                if (node.iterators[1]) |r| {
                    r.iterators[0] = node.iterators[0];
                } else {
                    self.iterators.ends[1] = node.iterators[0];
                    if (node.iterators[0]) |l| {
                        l.iterators[1] = null;
                    }
                }
            }
        }

        fn fixDoubleBlack(self: *@This(), node: *NodeType) void {
            // situation: node is a black leaf
            // simply deleteing node will harm blackness height rule
            //
            //        P(X)  Cast:
            //       /      C - current node   P - parent   (R) - red   (X) - unknown
            //      C(B)    S - sibling        N - newphew  (B) - black
            //
            // the solution is to push double black up the tree until fixed
            // think of current_node as node we want to recolor as red
            // (removing node has the same effect on black height)
            var current_node = node;
            while (current_node.par) |current_node_par| {
                const current_node_dir = current_node.direction();
                var current_node_sibling = current_node.sibling();
                // red sibling case. Make it black sibling case
                //
                //         P(X)                S(B)
                //       /     \    ----->    /   \
                //     C(B)    S(R)         P(R)   Z(B)
                //             / \          / \
                //           W(B) Z(B)  C(B)  W(B)
                //
                // W and Z should be black, as S is red (check rbtree invariants)
                // This transformation leaves us with black sibling
                if (current_node_sibling) |sibling| {
                    if (sibling.color == .red) {
                        self.rotate(current_node_par, current_node_dir);
                        sibling.color = .black;
                        current_node_par.color = .red;
                        current_node_sibling = current_node.sibling();
                    }
                }
                // p subtree at this exact moment
                //
                //       P(X)
                //      /   \
                //    C(B)  S(B) (W is renamed to S)
                //
                // sibling should exist, otherwise there are two paths
                // from parent with different black heights
                var sibling = current_node_sibling.?;
                // if both children of sibling are black, and parent is black too, there is easy fix
                const left_sibling_black = NodeType.colorOrBlack(sibling.desc[0]) == .black;
                const right_sibling_black = NodeType.colorOrBlack(sibling.desc[1]) == .black;
                if (left_sibling_black and right_sibling_black) {
                    if (current_node_par.color == .black) {
                        //       P(B)                            P(B)
                        //      /   \                           /    \
                        //    C(B)  S(B)       -------->      C(B)  S(R)
                        //
                        // if parent is already black, we can't compensate changing S color to red
                        // (which changes black height) locally. Instead we jump to a new iteration
                        // of the loop, requesting to recolor P to red
                        sibling.color = .red;
                        current_node = current_node_par;
                        continue;
                    } else {
                        //       P(R)                            P(B)
                        //      /   \                           /    \
                        //    C(B)  S(B)       -------->      C(B)  S(R)
                        //
                        // in this case there is no need to fix anything else, as we compensated for
                        // changing S color to R with changing N's color to black. This means that
                        // black height on this path won't change at all.
                        current_node_par.color = .black;
                        sibling.color = .red;
                        return;
                    }
                }
                const parent_color = current_node_par.color;
                // check if red nephew has the same direction from parent
                if (NodeType.colorOrBlack(sibling.desc[current_node_dir]) == .red) {
                    //        P(X)                      P(X)
                    //       /   \                     /   \
                    //     C(B)  S(B)                C(B)  N(B)
                    //           /  \     ----->          /   \
                    //        N(R) Z(X)                X(B)   S(R)
                    //       /   \                           /   \
                    //     X(B)  Y(B)                      Y(B)  Z(X)
                    //
                    // exercise for the reader: check that black heights
                    // on paths from P to X, Y, and Z remain unchanged
                    // the purpose is to make this case right newphew case
                    // (in which direction of red nephew is opposite to direction of node)
                    self.rotate(sibling, 1 - current_node_dir);
                    sibling.color = .red;
                    // nephew exists and it will be a new subling
                    sibling = current_node.sibling().?;
                    sibling.color = .black;
                }
                //     P(X)                 S(P's old color)
                //    /   \                     /     \
                //  C(B)  S(B)    ----->      P(B)   N(B)
                //       /   \               /   \
                //     Y(X) N(R)           C(B)  Y(X)
                //
                // The black height on path from P to Y is the same as on path from S to Y in a new
                // tree. The black height on path from P to N is the same as on path from S to N in
                // a new tree. We only increased black height on path from P/S to C. But that is
                // fine, since recoloring C to red or deleting it is our final goal
                self.rotate(current_node_par, current_node_dir);
                current_node_par.color = .black;
                sibling.color = parent_color;
                if (sibling.desc[1 - current_node_dir]) |nephew| {
                    nephew.color = .black;
                }
                return;
            }
        }

        /// Remove helper
        fn removeImpl(self: *@This(), node: *NodeType) void {
            // We are only handling deletition of a node with at most one child
            self.replaceIfNeeded(node);
            const node_parent_nullable = node.par;
            // Get node's only child if any
            var node_child_nullable = node.desc[0];
            if (node_child_nullable == null) {
                node_child_nullable = node.desc[1];
            }
            const node_dir = node.direction();
            if (node_child_nullable) |child| {
                // If child exist and is the only child, it must be red
                // otherwise
                if (node_parent_nullable) |parent| {
                    parent.desc[node_dir] = child;
                    child.par = parent;
                } else {
                    self.root = child;
                    child.par = null;
                }
                child.color = .black;
                self.cutFromIterList(node);
                // calling augment callback only after all updates
                if (node_parent_nullable) |parent| {
                    updatePathAugment(parent);
                    updatePathSubtreeSizes(parent);
                }
                self.size -= 1;
                return;
            }
            if (node.color == .red) {
                // if color is red, node is not root, and parent should exist
                const parent = node_parent_nullable.?;
                parent.desc[node.direction()] = null;
                self.cutFromIterList(node);
                updatePathAugment(parent);
                updatePathSubtreeSizes(parent);
                self.size -= 1;
                return;
            }
            if (node_parent_nullable) |parent| {
                // hard case: double black
                self.fixDoubleBlack(node);
                parent.desc[node.direction()] = null;
                self.cutFromIterList(node);
                updatePathAugment(parent);
                updatePathSubtreeSizes(parent);
            } else {
                // node is simply root with no children
                self.root = null;
                self.cutFromIterList(node);
            }
            self.size -= 1;
        }

        /// Removes element from the red black tree
        pub fn remove(self: *@This(), node: *T) void {
            self.removeImpl(refToNode(node));
        }

        /// Helper for upper and lower bound functions
        fn boundInDirection(
            self: *const @This(),
            comptime Predicate: type,
            pred: *const Predicate,
            dir: u1,
        ) ?*T {
            comptime {
                if (!@hasDecl(Predicate, "check")) {
                    @compileError("Predicate type should define \"check\" function");
                }
                const ExpectedPredicateType = fn (*const Predicate, *const T) bool;
                if (@TypeOf(Predicate.check) != ExpectedPredicateType) {
                    @compileError("Invalid type of check function");
                }
            }
            var candidate: ?*NodeType = null;
            var current_nullable = self.root;
            while (current_nullable) |current| {
                if (pred.check(nodeToRef(current))) {
                    candidate = current;
                    current_nullable = current.desc[dir];
                } else {
                    current_nullable = current.desc[1 - dir];
                }
            }
            return nodeToRefOpt(candidate);
        }

        /// Find the rightmost node for which predicate returns true
        pub fn upperBound(
            self: *const @This(),
            comptime predicate: type,
            pred: *const predicate,
        ) ?*T {
            return self.boundInDirection(predicate, pred, 1);
        }

        /// Find the leftmost node for which predicate returns true
        pub fn lowerBound(
            self: *const @This(),
            comptime predicate: type,
            pred: *const predicate,
        ) ?*T {
            return self.boundInDirection(predicate, pred, 0);
        }

        /// Initialize empty red black tree
        pub fn init(
            comp: cfg.comparator,
            augment_callback: if (cfg.augment_callback) |callback| callback else void,
        ) @This() {
            return .{
                .root = null,
                .iterators = if (enable_iterators_cache) .{ .ends = .{ null, null } } else {},
                .comparator = comp,
                .augment_callback = augment_callback,
                .size = 0,
                .kth = if (enable_kth_queries) .{ .temp_fix = 0 } else {},
            };
        }
    };
}

// TODO: add test to cover augmented cases (which for now may be just plain wrong)
test "red black tree" {
    const features = Features{
        .enable_iterators_cache = true,
        .enable_kth_queries = true,
        .enable_not_associatve_augment = false,
    };

    const IntTreeNode = struct {
        val: usize, hook: Node(features) = undefined
    };

    const IntComparator = struct {
        pub fn compare(
            self: *const @This(),
            left: *const IntTreeNode,
            right: *const IntTreeNode,
        ) bool {
            return left.val >= right.val;
        }
    };

    const int_tree_config = Config{
        .features = features,
        .augment_callback = null,
        .comparator = IntComparator,
    };

    const TreeType = Tree(IntTreeNode, "hook", int_tree_config);
    var tree = TreeType.init(.{}, {});

    const InorderListItem = struct {
        val: usize,
        color: Color,
    };

    const generate_inorder = struct {
        pub fn generateInOrder(node: ?*IntTreeNode, trace: []InorderListItem, pos: usize) usize {
            if (node) |node_nonnull| {
                if (node_nonnull.hook.par) |parent| {
                    const cond = parent.desc[node_nonnull.hook.direction()] == &(node_nonnull.hook);
                    std.debug.assert(cond);
                }
                var current_pos = pos;
                current_pos = generateInOrder(
                    TreeType.nodeToRefOpt(node_nonnull.hook.desc[0]),
                    trace,
                    current_pos,
                );
                trace[current_pos].color = node_nonnull.hook.color;
                trace[current_pos].val = node_nonnull.val;
                return generateInOrder(
                    TreeType.nodeToRefOpt(node_nonnull.hook.desc[1]),
                    trace,
                    current_pos + 1,
                );
            }
            return pos;
        }
    }.generateInOrder;

    const verifyInOrder = struct {
        fn verifyInOrder(trace: []InorderListItem, result: []InorderListItem) bool {
            for (result) |elem, i| {
                if (trace[i].color != elem.color or trace[i].val != elem.val) {
                    return false;
                }
            }
            return true;
        }
    }.verifyInOrder;

    // Insertion test
    var nodes = [_]IntTreeNode{
        .{ .val = 7 },
        .{ .val = 3 },
        .{ .val = 18 },
        .{ .val = 10 },
        .{ .val = 22 },
        .{ .val = 8 },
        .{ .val = 11 },
        .{ .val = 26 },
        .{ .val = 2 },
        .{ .val = 6 },
        .{ .val = 13 },
    };

    for (nodes) |*node| {
        tree.insert(node);
    }

    var inorder: [11]InorderListItem = undefined;
    _ = generate_inorder(TreeType.nodeToRefOpt(tree.root), &inorder, 0);

    var expected_result = [_]InorderListItem{
        .{ .val = 2, .color = .red },
        .{ .val = 3, .color = .black },
        .{ .val = 6, .color = .red },
        .{ .val = 7, .color = .red },
        .{ .val = 8, .color = .black },
        .{ .val = 10, .color = .black },
        .{ .val = 11, .color = .black },
        .{ .val = 13, .color = .red },
        .{ .val = 18, .color = .red },
        .{ .val = 22, .color = .black },
        .{ .val = 26, .color = .red },
    };

    std.testing.expect(verifyInOrder(&inorder, &expected_result));

    // Queries test
    const UpperBoundSearchPredicate = struct {
        val: usize,
        fn check(self: *const @This(), node: *const IntTreeNode) bool {
            return node.val <= self.val;
        }
    };

    const query = struct {
        fn query(t: *const TreeType, val: usize) ?*IntTreeNode {
            const pred = UpperBoundSearchPredicate{ .val = val };
            return t.upperBound(UpperBoundSearchPredicate, &pred);
        }
    }.query;

    tree.remove(query(&tree, 18).?);
    tree.remove(query(&tree, 11).?);
    tree.remove(query(&tree, 3).?);
    tree.remove(query(&tree, 10).?);
    tree.remove(query(&tree, 22).?);

    std.testing.expect(query(&tree, 16).?.val == 13);
    std.testing.expect(query(&tree, 0) == null);

    _ = generate_inorder(TreeType.nodeToRefOpt(tree.root), &inorder, 0);

    var expected_result2 = [_]InorderListItem{
        .{ .val = 2, .color = .black },
        .{ .val = 6, .color = .red },
        .{ .val = 7, .color = .black },
        .{ .val = 8, .color = .black },
        .{ .val = 13, .color = .black },
        .{ .val = 26, .color = .red },
    };

    std.testing.expect(verifyInOrder(&inorder, &expected_result2));

    std.testing.expect(tree.kth.at(0).?.val == 2);
    std.testing.expect(tree.kth.at(1).?.val == 6);
    std.testing.expect(tree.kth.at(2).?.val == 7);
    std.testing.expect(tree.kth.at(3).?.val == 8);
    std.testing.expect(tree.kth.at(4).?.val == 13);
    std.testing.expect(tree.kth.at(5).?.val == 26);
    std.testing.expect(tree.kth.at(6) == null);

    // Check size
    std.testing.expect(tree.size == 6);
}
