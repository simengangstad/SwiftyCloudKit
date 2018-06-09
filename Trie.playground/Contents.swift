class TrieNode<T: Hashable> {
    var value: T?
    weak var parent: TrieNode?
    var children: [T: TrieNode] = [:]
    fileprivate(set) public var isTerminating = false
    fileprivate(set) public var isLeaf = false
    
    init(value: T? = nil, parent: TrieNode? = nil) {
        self.value = value
        self.parent = parent
    }
    
    func add(child: T) {
        guard children[child] == nil else {
            return
        }
        
        children[child] = TrieNode(value: child, parent: self)
    }
}

class Trie {
    typealias Node = TrieNode<Character>
    fileprivate let root: Node
    fileprivate(set) public var wordCount = 0
    
    init() {
        root = Node()
    }
}

extension Trie {
    func insert(word: String) {
        guard !word.isEmpty else {
            return
        }
        
        var current = root
        
        let characters = Array(word.lowercased())
        var index = 0
        
        while index < characters.count {
            let character = characters[index]
            
            if let child = current.children[character] {
                current = child
            }
            else {
                current.isLeaf = false
                current.add(child: character)
                current = current.children[character]!
            }
            
            index += 1
            
            if index == characters.count {
                current.isTerminating = true
                
                if current.children.isEmpty {
                    current.isLeaf = true
                }
            }
        }
        
        wordCount += 1
    }
    
    func remove(word: String) {
        guard let terminalNode = terminalNode(of: word) else {
            return
        }
        
        if terminalNode.isLeaf {
            deleteNodesForWordEnding(with: terminalNode)
        }
        else {
            terminalNode.isTerminating = false
        }
        
        wordCount -= 1
    }
    
    func contains(word: String) -> Bool {
        return terminalNode(of: word) != nil
    }
    
    private func terminalNode(of word: String) -> Node? {
        guard !word.isEmpty else {
            return nil
        }
        
        var current = root
        
        let characters = Array(word.lowercased())
        var index = 0
        
        while index < characters.count, let child = current.children[characters[index]] {
            current = child
            index += 1
        }
        
        if index == characters.count && current.isTerminating {
            return current
        }
        
        return nil
    }
    
    private func deleteNodesForWordEnding(with terminalNode: Node) {
        var current = terminalNode
        
        while (current.parent?.children.count)! < 2 {
            
            current = current.parent!
            current.children.removeAll()
        }
        
        current.parent?.children.removeValue(forKey: current.value!)
    }
}

let trie = Trie()
trie.insert(word: "cute")
trie.insert(word: "cut")
trie.insert(word: "cus")
trie.contains(word: "cus")
trie.remove(word: "cus")
trie.contains(word: "cus")
